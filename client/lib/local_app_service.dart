import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'crypto/aes_bytes.dart';
import 'local_database_service.dart';
import 'logging/logger.dart';
import 'p2p_service.dart';
import 'services/attachments/attachment_service.dart';
import 'services/calls/call_history_service.dart';
import 'services/contacts/contact_service.dart';
import 'services/identity/identity_service.dart';
import 'services/messaging/message_service.dart';
import 'storage_service.dart';

class LocalAppService {
  LocalAppService() {
    // Wire group-encryption callbacks into MessageService and
    // AttachmentService. Group secrets still live in LocalAppService
    // (deferred until a dedicated GroupEncryptionService is extracted).
    _messages.attachGroupCrypto(
      encryptGroup: _encryptGroupMessage,
      decryptGroup: _decryptGroupMessage,
    );
    _messages.attachAttachmentCompactor(_attachments.compactDescriptor);
    _attachments.attachGroupKeyResolver(_loadOrCreateGroupSecretKey);
    // Tasks #9 + #12: fire-and-forget background workers. Both touch
    // LocalDatabaseService (which needs path_provider / IndexedDB
    // platform bindings); in unit tests without TestWidgetsFlutterBinding
    // the calls throw. We swallow those errors so test setup that
    // constructs LocalAppService doesn't fail just because the DB
    // backend isn't wired.
    unawaited(_kickoffBackgroundWorkers());
  }

  Future<void> _kickoffBackgroundWorkers() async {
    try {
      await P2PService.instance.startRetryWorker();
    } catch (error) {
      Logger.debug(
        '[bootstrap] retry worker deferred (likely test env / DB unavailable)',
        extras: {'error': error},
      );
    }
    try {
      await _attachments.evictOldBlobs();
    } catch (error) {
      Logger.debug(
        '[bootstrap] attachment eviction deferred (likely test env / DB unavailable)',
        extras: {'error': error},
      );
    }
  }

  final StorageService _storage = StorageService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final Uuid _uuid = const Uuid();
  final AesGcm _aes = AesGcm.with256bits();
  final IdentityService _identity = IdentityService();
  final ContactService _contacts = ContactService();
  final MessageService _messages = MessageService();
  final AttachmentService _attachments = AttachmentService();
  final CallHistoryService _callHistory = CallHistoryService();
  final Map<String, SecretKey> _groupSecretCache = {};

  // Byte-level AES-GCM encrypt/decrypt now lives in
  // `client/lib/crypto/aes_bytes.dart` (top-level `encryptBytesWithSecret`
  // / `decryptBytesWithSecret`). Chat-shape / shared-secret helpers moved
  // to MessageService (task #6). Attachment helpers and group-encryption
  // code reach them via `_messages.{getSharedSecret,isGroupChat,
  // getOtherUserId}` + the top-level crypto helpers.

  // Message-domain methods delegate to MessageService (task #6). The
  // group-encryption callbacks are wired in this class's constructor.

  Future<String> encryptMessage(
    String content,
    String otherUserId, {
    int? ratchetIndex,
  }) =>
      _messages.encryptMessage(content, otherUserId,
          ratchetIndex: ratchetIndex);

  Future<String> decryptMessage(
    String payload,
    String otherUserId, {
    int? ratchetIndex,
    bool senderIsMe = false,
  }) =>
      _messages.decryptMessage(payload, otherUserId,
          ratchetIndex: ratchetIndex, senderIsMe: senderIsMe);

  Future<Map<String, dynamic>> decryptRawMessage(
          Map<String, dynamic> row) =>
      _messages.decryptRawMessage(row);

  Future<SecretKey> _loadOrCreateGroupSecretKey(String chatId) async {
    if (_groupSecretCache.containsKey(chatId)) {
      return _groupSecretCache[chatId]!;
    }
    final keyName = 'group_key_$chatId';
    final stored = await _storage.read(keyName);
    if (stored != null && stored.isNotEmpty) {
      final key = SecretKey(base64Decode(stored));
      _groupSecretCache[chatId] = key;
      return key;
    }
    final key = await _aes.newSecretKey();
    await _storage.write(keyName, base64Encode(await key.extractBytes()));
    _groupSecretCache[chatId] = key;
    return key;
  }

  Future<String> _encryptGroupMessage(String chatId, String content) async {
    final key = await _loadOrCreateGroupSecretKey(chatId);
    return encryptBytesWithSecret(Uint8List.fromList(utf8.encode(content)), key);
  }

  Future<String> _decryptGroupMessage(String chatId, String payload) async {
    final key = await _loadOrCreateGroupSecretKey(chatId);
    final bytes = await decryptBytesWithSecret(payload, key);
    return utf8.decode(bytes);
  }

  // Identity-domain methods delegate to IdentityService (task #5).
  Future<String?> getUserId() => _identity.getUserId();

  Future<String?> getNickname() => _identity.getNickname();

  Future<void> updateNickname(String nickname) async {
    await _identity.updateNickname(nickname);
    final me = await _identity.getUserId();
    if (me != null) _contacts.invalidateNicknameFor(me);
  }

  Future<void> registerUser(String nickname) => _identity.registerUser(nickname);

  Future<void> logout() async {
    await _identity.logout();
    _messages.clearCaches();
    _groupSecretCache.clear();
    _contacts.clearCaches();
  }

  Future<String> generateQRCode() => _identity.generateQRCode();

  // Attachment helpers (_normalizeBase64Url + _compactLocalAttachmentDescriptor)
  // moved to AttachmentService (task #7). LocalAppService accesses them via
  // `_attachments.compactDescriptor(...)` (wired into MessageService in the
  // constructor) and never directly.

  Future<String?> findOrCreatePrivateChatWith(String otherUserId) async {
    final me = await getUserId();
    if (me == null || me.isEmpty || otherUserId.isEmpty) {
      return null;
    }
    final existing = await _localDb.getChats();
    for (final chat in existing) {
      final isPrivate = chat['is_private'] as bool? ?? false;
      final members = (chat['members'] as List<dynamic>? ?? [])
          .map((member) => member.toString())
          .toSet();
      if (isPrivate && members.contains(me) && members.contains(otherUserId)) {
        return chat['id']?.toString();
      }
    }

    final now = DateTime.now().toIso8601String();
    final chatId = _uuid.v4();
    await _localDb.saveChat({
      'id': chatId,
      'name': null,
      'is_private': true,
      'members': [me, otherUserId],
      'created_at': now,
      'updated_at': now,
      'last_read_at': now,
    });
    Logger.info(
      '[local-only] created private chat',
      extras: {'chatId': chatId},
    );
    return chatId;
  }

  Future<String?> createGroupChat({
    required String name,
    required List<String> memberIds,
  }) async {
    final me = await getUserId();
    if (me == null || me.isEmpty) return null;
    final members = <String>{me, ...memberIds}.toList();
    final now = DateTime.now().toIso8601String();
    final chatId = _uuid.v4();
    await _localDb.saveChat({
      'id': chatId,
      'name': name.trim().isEmpty ? 'Group' : name.trim(),
      'is_private': false,
      'members': members,
      'created_at': now,
      'updated_at': now,
      'last_read_at': now,
      'roles': {for (final id in members) id: id == me ? 'admin' : 'member'},
    });
    await _loadOrCreateGroupSecretKey(chatId);
    return chatId;
  }

  Future<List<Map<String, dynamic>>> getChatMembers(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    final members = (chat?['members'] as List<dynamic>? ?? [])
        .map((member) => member.toString())
        .toList();
    final roles = chat?['roles'] as Map<dynamic, dynamic>? ?? const {};
    return Future.wait(
      members.map((id) async {
        return {
          'user_id': id,
          'nickname': await getNicknameForUser(id) ?? id,
          'role': roles[id]?.toString() ?? 'member',
        };
      }),
    );
  }

  Future<String?> getMyRoleInChat(String chatId) async {
    final me = await getUserId();
    final chat = await _localDb.getChatById(chatId);
    final roles = chat?['roles'] as Map<dynamic, dynamic>? ?? const {};
    return roles[me]?.toString() ?? 'member';
  }

  Future<void> addMembersToGroupChat({
    required String chatId,
    required List<String> memberIds,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    final members = (chat['members'] as List<dynamic>? ?? [])
        .map((member) => member.toString())
        .toSet()
      ..addAll(memberIds);
    chat['members'] = members.toList();
    chat['updated_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }

  Future<void> removeMemberFromGroupChat({
    required String chatId,
    required String userId,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    final members = (chat['members'] as List<dynamic>? ?? [])
        .map((member) => member.toString())
        .where((member) => member != userId)
        .toList();
    chat['members'] = members;
    chat['updated_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }

  Future<void> updateGroupMemberRole({
    required String chatId,
    required String userId,
    required String role,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    final roles = Map<String, dynamic>.from(chat['roles'] as Map? ?? {});
    roles[userId] = role;
    chat['roles'] = roles;
    chat['updated_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }

  Future<List<dynamic>> getChats() async {
    final chats = await _localDb.getChats();
    chats.sort(
      (a, b) => (b['updated_at']?.toString() ?? '')
          .compareTo(a['updated_at']?.toString() ?? ''),
    );
    return chats;
  }

  Future<List<dynamic>> getMessages(
    String chatId, {
    int limit = 40,
    int offset = 0,
  }) =>
      _messages.getMessages(chatId, limit: limit, offset: offset);

  Future<void> sendMessage({
    required String chatId,
    required String content,
    required String type,
    String? replyToId,
    Map<String, dynamic>? metadataOverride,
  }) =>
      _messages.sendMessage(
        chatId: chatId,
        content: content,
        type: type,
        replyToId: replyToId,
        metadataOverride: metadataOverride,
      );

  Future<void> editMessage({
    required String messageId,
    required String chatId,
    required String content,
  }) =>
      _messages.editMessage(
          messageId: messageId, chatId: chatId, content: content);

  Future<void> softDeleteMessage({required String messageId}) =>
      _messages.softDeleteMessage(messageId: messageId);

  Future<void> pinMessage({
    required String chatId,
    required String messageId,
  }) =>
      _messages.pinMessage(chatId: chatId, messageId: messageId);

  Future<void> unpinMessage({required String chatId}) =>
      _messages.unpinMessage(chatId: chatId);

  Future<Map<String, dynamic>?> getPinnedMessage(String chatId) =>
      _messages.getPinnedMessage(chatId);

  // Attachment-domain methods delegate to AttachmentService (task #7).
  Future<String?> uploadAttachmentBytes({
    required Uint8List bytes,
    required String fileName,
    required String chatId,
    bool encrypt = true,
    bool? isGroupChat,
  }) =>
      _attachments.uploadBytes(
        bytes: bytes,
        fileName: fileName,
        chatId: chatId,
        encrypt: encrypt,
        isGroupChat: isGroupChat,
      );

  Future<Uint8List?> downloadAttachment(
    String url,
    String chatId, {
    bool encrypted = true,
    bool? isGroupChat,
  }) =>
      _attachments.download(url, chatId,
          encrypted: encrypted, isGroupChat: isGroupChat);

  Future<Map<String, dynamic>> getStorageDebugSummary() =>
      _attachments.getStorageDebugSummary();

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final chats = await _localDb.getChats();
    final contacts = await _localDb.getContacts();
    final calls = await _localDb.getCalls();
    var messageCount = 0;
    for (final chat in chats) {
      messageCount += (await _localDb.getMessages(chat['id'].toString())).length;
    }
    return {
      'chatCount': chats.length,
      'contactCount': contacts.length,
      'messageCount': messageCount,
      'callCount': calls.length,
      'localMediaReady': true,
      'bucketReady': true,
      'secureStorageReady': await _storage.read('privateKey') != null,
    };
  }

  Future<List<double>> getWeeklyActivityBars() async {
    final counts = List<int>.filled(7, 0);
    final now = DateTime.now();
    for (final chat in await _localDb.getChats()) {
      for (final message in await _localDb.getMessages(chat['id'].toString())) {
        final created = DateTime.tryParse(message['created_at']?.toString() ?? '');
        if (created == null) continue;
        final diff = now.difference(created).inDays;
        if (diff >= 0 && diff < 7) {
          counts[6 - diff] += 1;
        }
      }
    }
    final maxCount = counts.fold<int>(1, (max, value) => value > max ? value : max);
    return counts.map((count) => count == 0 ? 0.12 : count / maxCount).toList();
  }

  Future<Map<String, dynamic>?> fetchLastMessage(String chatId) =>
      _messages.fetchLastMessage(chatId);

  Future<DateTime?> getLastSeen(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    return DateTime.tryParse(chat?['last_read_at']?.toString() ?? '');
  }

  Future<int> countUnreadSince(String chatId, DateTime since) async {
    final me = await getUserId();
    final messages = await _localDb.getMessages(chatId);
    return messages.where((message) {
      final created = DateTime.tryParse(message['created_at']?.toString() ?? '');
      return message['sender_id'] != me && created != null && created.isAfter(since);
    }).length;
  }

  // Contact-domain methods delegate to ContactService (task #5).
  Future<List<dynamic>> getContacts() => _contacts.getContacts();

  Future<void> deleteContact(String userId) => _contacts.deleteContact(userId);

  Future<void> getNicknames(Set<String> userIds) =>
      _contacts.getNicknames(userIds);

  Future<String?> getNicknameForUser(String userId) =>
      _contacts.getNicknameForUser(userId);

  Future<String?> getUserNicknameById(String userId) =>
      _contacts.getUserNicknameById(userId);

  Future<String?> getUserNickname() => _contacts.getUserNickname();

  Future<String?> getSafetyNumber(String otherUserId) =>
      _contacts.getSafetyNumber(otherUserId);

  Future<void> addContact(String userId) => _contacts.addContact(userId);

  Future<List<dynamic>> searchUsers(String query) =>
      _contacts.searchUsers(query);

  Future<void> markChatRead(String chatId) => _messages.markChatRead(chatId);

  /// User-initiated retry of a failed outgoing 1:1 message (task #10
  /// failed-state UI tap). Delegates to MessageService → P2PService.
  Future<void> retryNow(String messageId) => _messages.retryNow(messageId);

  Future<void> setTypingStatus({
    required String chatId,
    required bool isTyping,
  }) async {
    Logger.debug(
      '[local-only] typing status local-only',
      extras: {'chatId': chatId, 'isTyping': isTyping},
    );
  }

  Future<DateTime?> getOtherLastReadAt(String chatId) async => null;

  void subscribeP2PSignaling(String chatId) {
    unawaited(P2PService.instance.subscribeSignaling(chatId));
  }

  // Call-history methods delegate to CallHistoryService (task #7).
  Future<void> recordIncomingCall({
    required String chatId,
    required String fromUserId,
    required String fromNickname,
  }) =>
      _callHistory.recordIncomingCall(
        chatId: chatId,
        fromUserId: fromUserId,
        fromNickname: fromNickname,
      );

  Future<void> markIncomingCallDeclined({
    required String chatId,
    required String fromUserId,
  }) =>
      _callHistory.markIncomingCallDeclined(
          chatId: chatId, fromUserId: fromUserId);

  Future<void> markCurrentUserCallEnded({required String chatId}) =>
      _callHistory.markCurrentUserCallEnded(chatId: chatId);

  Future<List<Map<String, dynamic>>> getRecentCallHistory({int limit = 5}) =>
      _callHistory.getRecentCallHistory(limit: limit);
}
