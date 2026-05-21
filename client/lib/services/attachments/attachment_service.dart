import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../../crypto/aes_bytes.dart';
import '../../local_database_service.dart';
import '../../logging/logger.dart';
import '../messaging/message_service.dart';

/// Wire-format version for the `local-attachment:` envelope.
///   v1 — legacy inline payload (full encrypted blob carried inline in
///        the message body, doubling storage). Read-only support.
///   v2 — descriptor-only (blobId + sha256 + size + mime + fileName);
///        blob bytes flow via the P2P chunked `blob-request` /
///        `blob-chunk` protocol (task #11).
const int kAttachmentWireVersion = 2;

/// Encrypted attachment store + wire format for the local-first chat.
///
/// Attachments live in the `attachments` IndexedDB / Sembast store
/// keyed by a UUID. The wire format is a `local-attachment:<base64url>`
/// descriptor — currently v1 (inline base64 payload). Task #11 replaces
/// the wire shape with v2 (descriptor-only + chunked DC frames); v1 read
/// path stays for backward compatibility.
///
/// Group-secret resolution is supplied by [LocalAppService] via
/// [attachGroupKeyResolver] (mirrors the MessageService callback pattern
/// in task #6) so AttachmentService doesn't need a back-reference.
///
/// Extracted from `LocalAppService` as task #7 of the post-PocketBase
/// hardening plan (`.ai-factory/plans/client-hardening-followup.md`).
class AttachmentService {
  factory AttachmentService() => _instance;
  AttachmentService._();
  static final AttachmentService _instance = AttachmentService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final MessageService _messages = MessageService();
  final Uuid _uuid = const Uuid();

  Future<SecretKey> Function(String chatId)? _groupKeyResolver;

  /// Wires the group-secret-key resolver from `LocalAppService`. MUST be
  /// called once during bootstrap — group attachment uploads / downloads
  /// throw without it.
  void attachGroupKeyResolver(
      Future<SecretKey> Function(String chatId) resolver) {
    _groupKeyResolver = resolver;
  }

  /// Encrypts [bytes], saves them under a fresh `blobId` in the local
  /// attachments store, and returns a `v: 2` wire descriptor with NO
  /// inline payload. The peer sees just the descriptor in the message
  /// envelope; the blob bytes ride a separate chunked transfer driven by
  /// `P2PService` (`blob-request` / `blob-chunk` frames, task #11).
  ///
  /// `encrypt: false` is accepted but ignored — attachments always land
  /// encrypted on disk (logged for visibility).
  Future<String?> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String chatId,
    bool encrypt = true,
    bool? isGroupChat,
    String? mime,
  }) async {
    final groupChat = isGroupChat ?? await _messages.isGroupChat(chatId);
    final otherUserId =
        groupChat ? null : await _messages.getOtherUserId(chatId);
    if (!groupChat && (otherUserId == null || otherUserId.isEmpty)) {
      return null;
    }
    final key = groupChat
        ? await _resolveGroupKey(chatId)
        : await _messages.getSharedSecret(otherUserId!);
    if (!encrypt) {
      Logger.info(
        '[attachments] attachments are stored encrypted; encrypt=false ignored',
      );
    }
    final encryptedPayload = await encryptBytesWithSecret(bytes, key);
    final encryptedBytes = base64Decode(encryptedPayload);
    final hashBytes = (await Sha256().hash(encryptedBytes)).bytes;
    final hash = base64UrlEncode(hashBytes).replaceAll('=', '');
    final blobId = _uuid.v4();
    await _localDb.saveAttachment({
      'id': blobId,
      'chatId': chatId,
      'fileName': fileName,
      'isGroupChat': groupChat,
      'encrypted': true,
      'payload': encryptedPayload,
      'hash': hash,
      'mime': mime,
      'size': bytes.length,
      'createdAt': DateTime.now().toIso8601String(),
    });
    final descriptor = <String, dynamic>{
      'v': 2,
      'blobId': blobId,
      'hash': hash,
      'size': bytes.length,
      if (mime != null) 'mime': mime,
      'fileName': fileName,
    };
    Logger.info('[attachments] uploaded (v2)', extras: {
      'chatId': chatId,
      'isGroupChat': groupChat,
      'size': bytes.length,
    });
    return 'local-attachment:${base64UrlEncode(
      utf8.encode(jsonEncode(descriptor)),
    )}';
  }

  /// Returns the (still-encrypted) blob bytes if present locally. Used by
  /// `P2PService` to chunk-send a blob after receiving a `blob-request`.
  Future<Uint8List?> readBlobBytes(String blobId) async {
    final row = await _localDb.getAttachment(blobId);
    if (row == null) return null;
    final payload = row['payload'] as String?;
    if (payload == null || payload.isEmpty) return null;
    return Uint8List.fromList(base64Decode(payload));
  }

  /// Saves a blob received via the chunked transfer. Caller (P2PService)
  /// has already verified sha256 over the full reassembled bytes. The
  /// `expectedHash` is stored too so future reads can re-verify.
  Future<void> saveReceivedBlob({
    required String blobId,
    required Uint8List encryptedBytes,
    required String hash,
    required String chatId,
    required String fileName,
    String? mime,
    bool? isGroupChat,
  }) async {
    final encryptedPayload = base64Encode(encryptedBytes);
    await _localDb.saveAttachment({
      'id': blobId,
      'chatId': chatId,
      'fileName': fileName,
      'isGroupChat': isGroupChat ?? false,
      'encrypted': true,
      'payload': encryptedPayload,
      'hash': hash,
      'mime': mime,
      'size': encryptedBytes.length,
      'createdAt': DateTime.now().toIso8601String(),
    });
    Logger.info('[attachments] received blob saved',
        extras: {'blobId': blobId, 'size': encryptedBytes.length});
  }

  /// True if a blob with [blobId] is already in the local store.
  Future<bool> hasBlob(String blobId) async {
    final row = await _localDb.getAttachment(blobId);
    return row != null && (row['payload']?.toString().isNotEmpty ?? false);
  }

  // -------------- Task #12: LRU eviction --------------

  /// Default upper bound for total encrypted blob bytes kept locally.
  /// 500 MB — configurable per-user later via a settings UI; the
  /// hardening-followup plan calls for `shared_preferences` plumbing
  /// in a follow-up.
  static const int defaultMaxTotalBytes = 500 * 1024 * 1024;

  /// Default maximum age before a blob is eligible for eviction. Pinned
  /// blobs are exempt regardless of age.
  static const Duration defaultMaxAge = Duration(days: 30);

  /// Walks every chat, reads the `pinned_message_id` field, fetches the
  /// pinned message (via [MessageService]) and extracts attachment ids
  /// from its decoded content. Pinned blobs are EXEMPT from eviction.
  ///
  /// Handles both wire shapes:
  ///   v1 — `{attachmentId, ...}` (legacy inline payload).
  ///   v2 — `{blobId, ...}` (task #11 descriptor-only).
  ///
  /// Cost: O(chatCount) `getPinnedMessage` calls. Typical scale is
  /// hundreds of chats × ≤ 1 pin per chat — acceptable on demand.
  Future<Set<String>> pinnedAttachmentIds() async {
    final ids = <String>{};
    final chats = await _localDb.getChats();
    for (final chat in chats) {
      final chatId = chat['id']?.toString();
      if (chatId == null || chatId.isEmpty) continue;
      final pinned = await _messages.getPinnedMessage(chatId);
      if (pinned == null) continue;
      final content = pinned['content']?.toString() ?? '';
      final id = parseLocalAttachmentId(content);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// One-shot eviction sweep. Drops oldest-first attachments until
  /// BOTH constraints are satisfied:
  ///   1. Total encrypted bytes ≤ [maxTotalBytes].
  ///   2. No attachment older than [maxAge].
  ///
  /// Pinned-message attachments are exempt. Returns the count of
  /// evicted rows. Safe to call repeatedly — no-op when nothing
  /// qualifies for eviction.
  Future<int> evictOldBlobs({
    int maxTotalBytes = defaultMaxTotalBytes,
    Duration maxAge = defaultMaxAge,
  }) async {
    final all = await _localDb.getAllAttachments();
    // Oldest-first so the first ones we evict are the natural LRU picks.
    all.sort((a, b) => (a['createdAt']?.toString() ?? '')
        .compareTo(b['createdAt']?.toString() ?? ''));

    final exempt = await pinnedAttachmentIds();

    var totalBytes = 0;
    for (final row in all) {
      totalBytes += _rowBytes(row);
    }

    final cutoff = DateTime.now().subtract(maxAge);
    var evictedCount = 0;
    var bytesFreed = 0;

    for (final row in all) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (exempt.contains(id)) continue;

      final createdAtStr = row['createdAt']?.toString() ?? '';
      final createdAt = DateTime.tryParse(createdAtStr);
      final rowBytes = _rowBytes(row);

      final evictByAge = createdAt != null && createdAt.isBefore(cutoff);
      final evictByCap = totalBytes > maxTotalBytes;

      if (!evictByAge && !evictByCap) continue;

      await _localDb.deleteAttachment(id);
      Logger.debug('[attachments] evicted', extras: {
        'blobId': id,
        'reason': evictByAge ? 'age' : 'cap',
        'size': rowBytes,
      });
      evictedCount += 1;
      bytesFreed += rowBytes;
      totalBytes -= rowBytes;
    }

    Logger.info('[attachments] eviction sweep complete', extras: {
      'evictedCount': evictedCount,
      'bytesFreed': bytesFreed,
      'remainingBytes': totalBytes,
      'pinnedExempt': exempt.length,
    });
    return evictedCount;
  }

  /// Best-effort byte count for an attachment row. Uses an explicit
  /// `size` field when present (set by [uploadBytes] and
  /// [saveReceivedBlob]); falls back to estimating from the base64
  /// `payload` length (× 3/4) for legacy rows.
  int _rowBytes(Map<String, dynamic> row) {
    final size = row['size'] as int?;
    if (size != null && size > 0) return size;
    final payload = row['payload']?.toString() ?? '';
    return (payload.length * 3) ~/ 4;
  }

  /// Decodes the wire descriptor (v1 inline-payload or v2 descriptor-only —
  /// the latter pulls bytes from the local attachments store via
  /// `attachmentId`) and returns the decrypted plaintext bytes.
  Future<Uint8List?> download(
    String url,
    String chatId, {
    bool encrypted = true,
    bool? isGroupChat,
  }) async {
    if (!url.startsWith('local-attachment:')) {
      return null;
    }
    try {
      final encoded = url.substring('local-attachment:'.length);
      final data = jsonDecode(
        utf8.decode(base64Url.decode(_normalizeBase64Url(encoded))),
      ) as Map<String, dynamic>;
      var payload = data['payload'] as String?;
      if (payload == null) {
        // v2 descriptors carry `blobId`; legacy compacted v1 descriptors
        // carry `attachmentId`. Same store, same lookup.
        final localId = (data['blobId'] ?? data['attachmentId'])?.toString();
        if (localId == null || localId.isEmpty) {
          return null;
        }
        final stored = await _localDb.getAttachment(localId);
        if (stored == null) return null;
        final storedChatId = stored['chatId']?.toString();
        if (storedChatId != null &&
            storedChatId.isNotEmpty &&
            storedChatId != chatId) {
          Logger.warn(
            '[attachments] chat mismatch',
            extras: {'chatId': chatId, 'storedChatId': storedChatId},
          );
          return null;
        }
        payload = stored['payload'] as String?;
        if (payload == null || payload.isEmpty) return null;
      }
      final descriptorEncrypted = data['encrypted'] as bool? ?? encrypted;
      if (!descriptorEncrypted) {
        return Uint8List.fromList(base64Decode(payload));
      }
      final groupChat = isGroupChat ??
          (data['isGroupChat'] as bool? ?? await _messages.isGroupChat(chatId));
      final key = groupChat
          ? await _resolveGroupKey(chatId)
          : await _messages
              .getSharedSecret((await _messages.getOtherUserId(chatId))!);
      return decryptBytesWithSecret(payload, key);
    } catch (error) {
      Logger.warn(
        '[attachments] download failed',
        extras: {'error': error},
      );
      return null;
    }
  }

  /// Strips the inline `payload` from a v1 descriptor — saves storage by
  /// keeping the local message row pointing at the attachments store via
  /// `attachmentId` only, while the wire copy (sent over P2P) keeps the
  /// full payload inline. Used by [MessageService.sendMessage].
  String compactDescriptor(String content) {
    if (!content.startsWith('local-attachment:')) return content;
    try {
      final encoded = content.substring('local-attachment:'.length);
      final data = jsonDecode(
        utf8.decode(base64Url.decode(_normalizeBase64Url(encoded))),
      ) as Map<String, dynamic>;
      if (!data.containsKey('payload') ||
          data['attachmentId']?.toString().isNotEmpty != true) {
        return content;
      }
      data.remove('payload');
      return 'local-attachment:${base64UrlEncode(
        utf8.encode(jsonEncode(data)),
      )}';
    } catch (_) {
      return content;
    }
  }

  /// Storage debug rollup — counts how many messages still carry the
  /// `local-attachment:` envelope. Surfaced in profile/diagnostics.
  Future<Map<String, dynamic>> getStorageDebugSummary() async {
    final messages = <Map<String, dynamic>>[];
    for (final chat in await _localDb.getChats()) {
      messages.addAll(await _localDb.getMessages(chat['id'].toString()));
    }
    final attachmentCount = messages
        .where((message) =>
            message['content']?.toString().startsWith('local-attachment:') ??
            false)
        .length;
    return {
      'localMediaReady': true,
      'bucketReady': true,
      'fileCount': attachmentCount,
      'bucketName': 'local encrypted storage',
    };
  }

  Future<SecretKey> _resolveGroupKey(String chatId) async {
    final resolver = _groupKeyResolver;
    if (resolver == null) {
      throw StateError(
          'AttachmentService.attachGroupKeyResolver was not called before group attachment access.');
    }
    return resolver(chatId);
  }

  String _normalizeBase64Url(String value) {
    final remainder = value.length % 4;
    return remainder == 0
        ? value
        : value.padRight(value.length + 4 - remainder, '=');
  }
}

/// Extracts the local attachment id from a `local-attachment:<base64url>`
/// content string. Returns `blobId` for v2 descriptors, `attachmentId`
/// for v1 legacy. `null` for non-attachment content or malformed input.
///
/// Pure top-level function — exposed so unit tests can hit both wire
/// shapes without spinning up the full service singleton chain. Used by
/// [AttachmentService.pinnedAttachmentIds] (task #12).
String? parseLocalAttachmentId(String content) {
  if (!content.startsWith('local-attachment:')) return null;
  try {
    final encoded = content.substring('local-attachment:'.length);
    final padded = encoded.padRight(
      encoded.length + (4 - encoded.length % 4) % 4,
      '=',
    );
    final data = jsonDecode(utf8.decode(base64Url.decode(padded)))
        as Map<String, dynamic>;
    final id = (data['blobId'] ?? data['attachmentId'])?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  } catch (_) {
    return null;
  }
}
