import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../crypto/aes_bytes.dart';
import '../../crypto/ratchet_service.dart';
import '../../local_database_service.dart';
import '../../logging/logger.dart';
import '../../p2p_service.dart';
import '../contacts/contact_service.dart';
import '../identity/identity_service.dart';

/// Encrypted message lifecycle: encrypt/decrypt 1:1, send, edit, soft
/// delete, pin, paginate, read marker. Singleton. Group encryption is
/// out of scope here — it stays in `LocalAppService` and is injected
/// through [attachGroupCrypto] before first use, so MessageService stays
/// unit-testable without spinning up the per-chat group-secret cache.
///
/// Extracted from `LocalAppService` as task #6 of the post-PocketBase
/// hardening plan (`.ai-factory/plans/client-hardening-followup.md`).
class MessageService {
  factory MessageService() => _instance;
  MessageService._();
  static final MessageService _instance = MessageService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final IdentityService _identity = IdentityService();
  final ContactService _contacts = ContactService();
  final X25519 _algorithm = X25519();
  final RatchetService _ratchet = RatchetService();
  final Uuid _uuid = const Uuid();
  final Map<String, SecretKey> _sharedSecretCache = {};

  Future<String> Function(String chatId, String content)? _encryptGroup;
  Future<String> Function(String chatId, String payload)? _decryptGroup;

  /// Optional callback supplied by `LocalAppService` to strip the inline
  /// `payload` from `local-attachment:` descriptors before saving the
  /// local row (the wire copy keeps it for P2P delivery). Defaults to
  /// identity when not wired so tests that ignore attachments still work.
  String Function(String content) _compactAttachmentDescriptor = (s) => s;

  /// Wires group encryption callbacks. MUST be called once during
  /// `LocalAppService` bootstrap — group sends throw if these are unset.
  void attachGroupCrypto({
    required Future<String> Function(String chatId, String content)
        encryptGroup,
    required Future<String> Function(String chatId, String payload)
        decryptGroup,
  }) {
    _encryptGroup = encryptGroup;
    _decryptGroup = decryptGroup;
  }

  /// Wires the attachment-descriptor compactor (drops inline payload
  /// before local persistence; the wire envelope keeps it).
  void attachAttachmentCompactor(String Function(String content) compactor) {
    _compactAttachmentDescriptor = compactor;
  }

  /// Drops the per-peer shared-secret cache. Called by
  /// `LocalAppService.logout` so the next session starts cold.
  void clearCaches() {
    _sharedSecretCache.clear();
  }

  // ----------------- public API: encryption -----------------

  Future<String> encryptMessage(
    String content,
    String otherUserId, {
    int? ratchetIndex,
  }) async {
    SecretKey key;
    if (ratchetIndex != null) {
      final myId = (await _identity.getUserId())!;
      final sharedSecret = await _getSharedSecret(otherUserId);
      final chains =
          await _ratchet.initializeChains(sharedSecret, myId, otherUserId);
      key =
          await _ratchet.getNthMessageKey(chains['mySendChain']!, ratchetIndex);
    } else {
      key = await _getSharedSecret(otherUserId);
    }
    return encryptBytesWithSecret(
      Uint8List.fromList(utf8.encode(content)),
      key,
    );
  }

  Future<String> decryptMessage(
    String payload,
    String otherUserId, {
    int? ratchetIndex,
    bool senderIsMe = false,
  }) async {
    try {
      if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(payload)) {
        return payload;
      }

      SecretKey key;
      if (ratchetIndex != null) {
        final myId = (await _identity.getUserId())!;
        final sharedSecret = await _getSharedSecret(otherUserId);
        final chains =
            await _ratchet.initializeChains(sharedSecret, myId, otherUserId);
        final chainKey =
            senderIsMe ? chains['mySendChain']! : chains['theirSendChain']!;
        key = await _ratchet.getNthMessageKey(chainKey, ratchetIndex);
      } else {
        key = await _getSharedSecret(otherUserId);
      }
      final decrypted = await decryptBytesWithSecret(payload, key);
      return utf8.decode(decrypted);
    } catch (error) {
      Logger.warn(
        '[messages] decryptMessage failed',
        extras: {'error': error},
      );
      return payload;
    }
  }

  Future<Map<String, dynamic>> decryptRawMessage(
    Map<String, dynamic> row,
  ) async {
    final message = Map<String, dynamic>.from(row);
    if (message['deleted_at'] != null) {
      return message;
    }

    final metadata = message['metadata'] as Map<String, dynamic>? ?? const {};
    final encryption = metadata['encryption'] as String?;
    final ratchetIndex = metadata['sender_ratchet_index'] as int?;
    final senderId = message['sender_id'] as String?;
    final me = await _identity.getUserId();

    try {
      if (encryption == 'group_e2e') {
        final decryptGroup = _decryptGroup;
        if (decryptGroup == null) {
          Logger.warn(
            '[messages] group decryption requested but no callback wired',
            extras: {'chatId': message['chat_id']},
          );
          return message;
        }
        message['content'] = await decryptGroup(
          message['chat_id'] as String,
          message['content'] as String,
        );
      } else {
        final otherUserId = senderId == me
            ? await _getOtherUserId(message['chat_id'] as String)
            : senderId;
        if (otherUserId != null && otherUserId.isNotEmpty) {
          message['content'] = await decryptMessage(
            message['content'] as String,
            otherUserId,
            ratchetIndex: ratchetIndex,
            senderIsMe: me != null && senderId == me,
          );
        }
      }
    } catch (error) {
      Logger.warn(
        '[messages] decryptRawMessage failed',
        extras: {'error': error},
      );
    }
    return message;
  }

  // ----------------- public API: queries -----------------

  Future<List<dynamic>> getMessages(
    String chatId, {
    int limit = 40,
    int offset = 0,
  }) async {
    final messages = await _localDb.getMessages(chatId);
    final visible = messages
        .where((message) => message['deleted_at'] == null)
        .map((message) => Map<String, dynamic>.from(message))
        .toList()
      ..sort(
        (a, b) => (a['created_at']?.toString() ?? '')
            .compareTo(b['created_at']?.toString() ?? ''),
      );
    final page = visible.skip(offset).take(limit).toList();
    return Future.wait(page.map(decryptRawMessage));
  }

  Future<Map<String, dynamic>?> fetchLastMessage(String chatId) async {
    final messages = await getMessages(chatId, limit: 1000);
    if (messages.isEmpty) return null;
    final list = messages.cast<Map<String, dynamic>>()
      ..sort(
        (a, b) => (a['created_at']?.toString() ?? '')
            .compareTo(b['created_at']?.toString() ?? ''),
      );
    return list.last;
  }

  Future<Map<String, dynamic>?> getPinnedMessage(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    final pinnedId = chat?['pinned_message_id']?.toString();
    if (pinnedId == null || pinnedId.isEmpty) return null;
    final messages = await getMessages(chatId, limit: 1000);
    for (final message in messages.cast<Map<String, dynamic>>()) {
      if (message['id'] == pinnedId) return message;
    }
    return null;
  }

  // ----------------- public API: write paths -----------------

  Future<void> sendMessage({
    required String chatId,
    required String content,
    required String type,
    String? replyToId,
    Map<String, dynamic>? metadataOverride,
  }) async {
    final me = await _identity.getUserId();
    if (me == null) return;

    final isGroupChat = await _isGroupChat(chatId);
    final otherUserId = isGroupChat ? null : await _getOtherUserId(chatId);
    if (!isGroupChat && (otherUserId == null || otherUserId.isEmpty)) {
      return;
    }
    final localMessages = await _localDb.getMessages(chatId);
    final ratchetIndex = isGroupChat
        ? null
        : localMessages
            .where(
              (message) =>
                  message['sender_id'] == me &&
                  (message['metadata'] as Map<String, dynamic>? ?? {})
                      .containsKey('sender_ratchet_index'),
            )
            .length;

    // Keep attachment payload inline for P2P delivery, but store only a
    // compact descriptor in this device's local message history.
    final localContent = _compactAttachmentDescriptor(content);
    String encryptedContent;
    String localEncryptedContent;
    try {
      if (isGroupChat) {
        final encryptGroup = _encryptGroup;
        if (encryptGroup == null) {
          throw StateError(
              'MessageService.attachGroupCrypto was not called before group send.');
        }
        encryptedContent = await encryptGroup(chatId, content);
        localEncryptedContent = localContent == content
            ? encryptedContent
            : await encryptGroup(chatId, localContent);
      } else {
        encryptedContent = await encryptMessage(
          content,
          otherUserId!,
          ratchetIndex: ratchetIndex,
        );
        localEncryptedContent = localContent == content
            ? encryptedContent
            : await encryptMessage(
                localContent,
                otherUserId,
                ratchetIndex: ratchetIndex,
              );
      }
    } catch (error) {
      Logger.warn(
        '[messages] sendMessage encryption blocked',
        extras: {'error': error},
      );
      return;
    }

    final metadata = <String, dynamic>{
      'encryption': isGroupChat ? 'group_e2e' : 'e2e',
      if (metadataOverride != null) ...metadataOverride,
      if (ratchetIndex != null) 'sender_ratchet_index': ratchetIndex,
    };
    final now = DateTime.now().toIso8601String();
    final messageMap = {
      'id': _uuid.v4(),
      'chat_id': chatId,
      'sender_id': me,
      'content': encryptedContent,
      'message_type': type,
      'reply_to_id': replyToId,
      'metadata': metadata,
      'created_at': now,
    };
    final localMessageMap = {
      ...messageMap,
      'content': localEncryptedContent,
    };

    final prefs = isGroupChat ? null : await SharedPreferences.getInstance();
    final useP2P = prefs?.getBool('useP2P') ?? true;

    // Task #8: outgoing-only delivery status.
    //   - Groups never go over P2P today → write 'sent' immediately (no
    //     retry, no ACK — the group transport is a separate future
    //     workstream tracked in the post-PocketBase hardening plan).
    //   - 1:1 with P2P enabled starts as 'pending'; the post-send block below
    //     flips it to 'sent' on a successful DataChannel handoff.
    //   - 1:1 with P2P disabled is local-only today, so no delivery marker is
    //     written; otherwise the retry worker would chase an impossible send.
    final String? initialStatus = isGroupChat
        ? 'sent'
        : useP2P
            ? 'pending'
            : null;
    final messageId = messageMap['id'] as String;
    await _localDb.saveMessage(localMessageMap,
        synced: true, deliveryStatus: initialStatus);
    final chat = await _localDb.getChatById(chatId);
    if (chat != null) {
      chat['updated_at'] = now;
      await _localDb.saveChat(chat);
    }

    if (!isGroupChat) {
      if (useP2P) {
        try {
          final delivered =
              await P2PService.instance.sendP2PMessage(chatId, messageMap);
          if (delivered) {
            await markSent(messageId);
            // Task #11: if the user-facing content is a v2 attachment
            // descriptor, push the blob bytes to the peer right after
            // the message arrives. Receiver assembles in the background
            // and saves to its own attachments store.
            await sendAttachmentChunksIfNeeded(chatId, content);
          } else {
            Logger.debug(
                '[messages] initial send returned false, row '
                'stays pending for retry worker',
                extras: {
                  'messageId': messageId,
                });
          }
        } catch (error) {
          Logger.warn('[messages] initial P2P send threw, row stays pending',
              extras: {'messageId': messageId, 'error': error});
        }
      } else {
        Logger.debug(
          '[messages] P2P disabled; outgoing row saved local-only',
          extras: {'messageId': messageId, 'chatId': chatId},
        );
      }
    }
  }

  /// If [content] is a v2 `local-attachment:` descriptor, kick off the
  /// chunked blob transfer right after the message envelope was sent.
  /// Fire-and-forget — if the DC closes mid-stream, the receiver's
  /// assembly never completes and the next outgoing send / retry
  /// re-chunks. Legacy v1 descriptors carry the payload inline already.
  Future<void> sendAttachmentChunksIfNeeded(
      String chatId, String content) async {
    if (!content.startsWith('local-attachment:')) return;
    try {
      final encoded = content.substring('local-attachment:'.length);
      final padded = encoded.padRight(
        encoded.length + (4 - encoded.length % 4) % 4,
        '=',
      );
      final data = jsonDecode(utf8.decode(base64Url.decode(padded)))
          as Map<String, dynamic>;
      if (data['v'] != 2) return; // v1: payload already inline, nothing to push
      final blobId = data['blobId']?.toString();
      final hash = data['hash']?.toString();
      final fileName = data['fileName']?.toString() ?? 'attachment';
      if (blobId == null || blobId.isEmpty || hash == null || hash.isEmpty) {
        return;
      }
      Logger.debug('[messages] kicking off v2 blob chunked transfer',
          extras: {'chatId': chatId, 'blobId': blobId});
      await P2PService.instance.sendBlobChunks(
        chatId: chatId,
        blobId: blobId,
        hash: hash,
        fileName: fileName,
        mime: data['mime']?.toString(),
      );
    } catch (error) {
      Logger.warn(
        '[messages] failed to parse outbound attachment descriptor, '
        'skipping chunked send',
        extras: {'error': error},
      );
    }
  }

  /// Lifecycle marker — outgoing 1:1 only. Called from the P2P send path
  /// after a successful DataChannel write, and from the task #9 retry
  /// worker after the same. No-op on missing row (legitimately deleted).
  Future<void> markSent(String messageId) =>
      _localDb.updateMessageDeliveryStatus(messageId, 'sent');

  /// Called by the inbound ACK handler in P2PService (task #9) once the
  /// peer confirms receipt. No-op on missing row.
  Future<void> markDelivered(String messageId) =>
      _localDb.updateMessageDeliveryStatus(messageId, 'delivered');

  /// Called by the retry worker after `maxRetries` attempts are
  /// exhausted (task #9).
  Future<void> markFailed(String messageId) =>
      _localDb.updateMessageDeliveryStatus(messageId, 'failed');

  /// User-initiated retry from the failed-state UI tap (task #10).
  /// Flips the row back to `pending` (so the next pump sees it) and
  /// asks `P2PService` to attempt delivery immediately, resetting the
  /// in-memory backoff state for the affected chat.
  Future<void> retryNow(String messageId) async {
    Logger.info('[messages] user-initiated retryNow',
        extras: {'messageId': messageId});
    await _localDb.updateMessageDeliveryStatus(messageId, 'pending');
    await P2PService.instance.retryNow(messageId);
  }

  Future<void> editMessage({
    required String messageId,
    required String chatId,
    required String content,
  }) async {
    final messages = await _localDb.getMessages(chatId);
    final existing = messages.firstWhere(
      (message) => message['id'] == messageId,
      orElse: () => <String, dynamic>{},
    );
    if (existing.isEmpty) return;
    final me = await _identity.getUserId();
    final isGroupChat = await _isGroupChat(chatId);
    final otherUserId = isGroupChat ? null : await _getOtherUserId(chatId);
    if (!isGroupChat && (otherUserId == null || otherUserId.isEmpty)) {
      return;
    }
    final metadata =
        (existing['metadata'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final ratchetIndex = metadata['sender_ratchet_index'] as int?;
    final String encrypted;
    if (isGroupChat) {
      final encryptGroup = _encryptGroup;
      if (encryptGroup == null) {
        throw StateError(
            'MessageService.attachGroupCrypto was not called before group edit.');
      }
      encrypted = await encryptGroup(chatId, content);
    } else {
      encrypted = await encryptMessage(
        content,
        otherUserId!,
        ratchetIndex: ratchetIndex,
      );
    }
    existing['content'] = encrypted;
    existing['edited_at'] = DateTime.now().toIso8601String();
    existing['sender_id'] = existing['sender_id'] ?? me;
    await _localDb.saveMessage(existing, synced: true);
  }

  Future<void> softDeleteMessage({required String messageId}) async {
    final chats = await _localDb.getChats();
    for (final chat in chats) {
      final messages = await _localDb.getMessages(chat['id'].toString());
      for (final message in messages) {
        if (message['id'] == messageId) {
          message['deleted_at'] = DateTime.now().toIso8601String();
          await _localDb.saveMessage(message, synced: true);
          return;
        }
      }
    }
  }

  Future<void> pinMessage({
    required String chatId,
    required String messageId,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    chat['pinned_message_id'] = messageId;
    await _localDb.saveChat(chat);
  }

  Future<void> unpinMessage({required String chatId}) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    chat.remove('pinned_message_id');
    await _localDb.saveChat(chat);
  }

  Future<void> markChatRead(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    chat['last_read_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }

  // ----------------- public helpers (also reused by attachment code) -----------------

  /// Exposed for `LocalAppService` attachment helpers — they share the
  /// same shared-secret cache so encrypting an attachment doesn't trigger
  /// a separate DH derivation.
  Future<SecretKey> getSharedSecret(String otherUserId) =>
      _getSharedSecret(otherUserId);

  Future<bool> isGroupChat(String chatId) => _isGroupChat(chatId);

  Future<String?> getOtherUserId(String chatId) => _getOtherUserId(chatId);

  // ----------------- private helpers -----------------

  Future<SecretKey> _getSharedSecret(String otherUserId) async {
    if (_sharedSecretCache.containsKey(otherUserId)) {
      return _sharedSecretCache[otherUserId]!;
    }
    final ownKeyPair = await _identity.getOwnKeyPair();
    final otherPublicKey = await _contacts.getOtherPublicKey(otherUserId);
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: ownKeyPair,
      remotePublicKey: otherPublicKey,
    );
    _sharedSecretCache[otherUserId] = sharedSecret;
    return sharedSecret;
  }

  Future<List<String>> _getChatMemberIds(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    final rawMembers = chat?['members'];
    if (rawMembers is List) {
      return rawMembers.map((member) => member.toString()).toList();
    }
    return const [];
  }

  Future<String?> _getOtherUserId(String chatId) async {
    final me = await _identity.getUserId();
    final members = await _getChatMemberIds(chatId);
    for (final member in members) {
      if (member != me) {
        return member;
      }
    }
    return null;
  }

  Future<bool> _isGroupChat(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    final isPrivate = chat?['is_private'];
    if (isPrivate is bool) {
      return !isPrivate;
    }
    return (await _getChatMemberIds(chatId)).length != 2;
  }
}
