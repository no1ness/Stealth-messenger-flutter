import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'crypto/ratchet_service.dart';
import 'local_database_service.dart';
import 'p2p_service.dart';
import 'storage_service.dart';

class LocalAppService {
  LocalAppService();

  /// How long after [rotateIdentityKeypair] the previous identity
  /// keypair stays in secure storage as a decryption fallback. After
  /// this window, in-flight messages encrypted to the old key can no
  /// longer be opened — keep it generously larger than typical
  /// message-delivery latency (offline peers, push wake-ups, etc.).
  static const Duration kPrevKeyGracePeriod = Duration(hours: 24);

  final StorageService _storage = StorageService();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final Uuid _uuid = const Uuid();
  final X25519 _algorithm = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final RatchetService _ratchet = RatchetService();
  final Map<String, SecretKey> _sharedSecretCache = {};
  final Map<String, SecretKey> _prevSharedSecretCache = {};
  final Map<String, SecretKey> _groupSecretCache = {};
  final Map<String, String?> _nicknameCache = {};
  final Map<String, Map<String, dynamic>> _lastSearchResults = {};

  Future<String> _encryptBytesWithSecret(
    Uint8List bytes,
    SecretKey secretKey,
  ) async {
    final secretBox = await _aes.encrypt(bytes, secretKey: secretKey);
    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    combined.setRange(0, secretBox.nonce.length, secretBox.nonce);
    combined.setRange(
      secretBox.nonce.length,
      secretBox.nonce.length + secretBox.cipherText.length,
      secretBox.cipherText,
    );
    combined.setRange(
      secretBox.nonce.length + secretBox.cipherText.length,
      combined.length,
      secretBox.mac.bytes,
    );
    return base64Encode(combined);
  }

  Future<Uint8List> _decryptBytesWithSecret(
    String payload,
    SecretKey secretKey,
  ) async {
    final combined = base64Decode(payload);
    const nonceLength = 12;
    const macLength = 16;
    final nonce = combined.sublist(0, nonceLength);
    final mac = Mac(combined.sublist(combined.length - macLength));
    final cipherText = combined.sublist(
      nonceLength,
      combined.length - macLength,
    );
    final clearText = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: secretKey,
    );
    return Uint8List.fromList(clearText);
  }

  Future<SimpleKeyPair> _getOwnKeyPair() async {
    final privateKeyBase64 = await _storage.read('privateKey');
    final publicKeyBase64 = await _storage.read('publicKey');
    if (privateKeyBase64 == null || publicKeyBase64 == null) {
      throw Exception('Keys not found. User might not be registered.');
    }

    return SimpleKeyPairData(
      base64Decode(privateKeyBase64),
      publicKey: SimplePublicKey(
        base64Decode(publicKeyBase64),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  Future<SimplePublicKey> _getOtherPublicKey(String userId) async {
    final me = await getUserId();
    if (userId == me) {
      final ownPublicKey = await _storage.read('publicKey');
      if (ownPublicKey == null || ownPublicKey.isEmpty) {
        throw Exception('Own public key is missing.');
      }
      return SimplePublicKey(
        base64Decode(ownPublicKey),
        type: KeyPairType.x25519,
      );
    }

    final contacts = await _localDb.getContacts();
    for (final contact in contacts) {
      final id = (contact['contact_user_id'] ?? contact['user_id'])?.toString();
      if (id == userId) {
        final publicKey = contact['public_key']?.toString();
        if (publicKey != null && publicKey.isNotEmpty) {
          return SimplePublicKey(
            base64Decode(publicKey),
            type: KeyPairType.x25519,
          );
        }
      }
    }
    throw Exception(
      'Missing public key for $userId. Add the contact from a Stealth contact bundle.',
    );
  }

  Future<SecretKey> _getSharedSecret(String otherUserId) async {
    if (_sharedSecretCache.containsKey(otherUserId)) {
      return _sharedSecretCache[otherUserId]!;
    }

    final ownKeyPair = await _getOwnKeyPair();
    final otherPublicKey = await _getOtherPublicKey(otherUserId);
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: ownKeyPair,
      remotePublicKey: otherPublicKey,
    );
    _sharedSecretCache[otherUserId] = sharedSecret;
    return sharedSecret;
  }

  /// Loads the previous-generation identity keypair if it still exists
  /// in secure storage **and** has not aged past [kPrevKeyGracePeriod].
  /// Returns `null` otherwise — the caller treats `null` as "no
  /// fallback available".
  ///
  /// Expired prev material is best-effort pruned so it cannot be used
  /// for decryption after the grace window — see [_prunePrevKeyIfExpired].
  Future<SimpleKeyPair?> _getPrevKeyPair() async {
    final prevPriv = await _storage.read('privateKey_prev');
    final prevPub = await _storage.read('publicKey_prev');
    final rotatedAtIso = await _storage.read('prev_rotated_at');
    if (prevPriv == null ||
        prevPriv.isEmpty ||
        prevPub == null ||
        prevPub.isEmpty ||
        rotatedAtIso == null ||
        rotatedAtIso.isEmpty) {
      return null;
    }
    final rotatedAt = DateTime.tryParse(rotatedAtIso);
    if (rotatedAt == null ||
        DateTime.now().difference(rotatedAt) > kPrevKeyGracePeriod) {
      await _prunePrevKey();
      return null;
    }
    return SimpleKeyPairData(
      base64Decode(prevPriv),
      publicKey: SimplePublicKey(
        base64Decode(prevPub),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  /// Shared secret derived from the **previous** identity keypair.
  /// Returns `null` when no usable prev keypair is available (none
  /// stored, or expired).
  Future<SecretKey?> _getPrevSharedSecret(String otherUserId) async {
    if (_prevSharedSecretCache.containsKey(otherUserId)) {
      return _prevSharedSecretCache[otherUserId];
    }
    final prevKeyPair = await _getPrevKeyPair();
    if (prevKeyPair == null) {
      return null;
    }
    final otherPublicKey = await _getOtherPublicKey(otherUserId);
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: prevKeyPair,
      remotePublicKey: otherPublicKey,
    );
    _prevSharedSecretCache[otherUserId] = sharedSecret;
    return sharedSecret;
  }

  /// Removes the prev keypair from secure storage and resets the
  /// associated cache.
  Future<void> _prunePrevKey() async {
    await _storage.delete('privateKey_prev');
    await _storage.delete('publicKey_prev');
    await _storage.delete('prev_rotated_at');
    _prevSharedSecretCache.clear();
  }

  /// Triggers prev-key cleanup if its `prev_rotated_at` is older than
  /// the grace window. Safe to call on every bootstrap.
  Future<void> _prunePrevKeyIfExpired() async {
    final rotatedAtIso = await _storage.read('prev_rotated_at');
    if (rotatedAtIso == null || rotatedAtIso.isEmpty) {
      return;
    }
    final rotatedAt = DateTime.tryParse(rotatedAtIso);
    if (rotatedAt == null ||
        DateTime.now().difference(rotatedAt) > kPrevKeyGracePeriod) {
      await _prunePrevKey();
      debugPrint('[FIX:local-only] pruned expired prev identity key');
    }
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
    final me = await getUserId();
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

  Future<String> encryptMessage(
    String content,
    String otherUserId, {
    int? ratchetIndex,
  }) async {
    SecretKey key;
    if (ratchetIndex != null) {
      final myId = (await getUserId())!;
      final sharedSecret = await _getSharedSecret(otherUserId);
      final chains =
          await _ratchet.initializeChains(sharedSecret, myId, otherUserId);
      key =
          await _ratchet.getNthMessageKey(chains['mySendChain']!, ratchetIndex);
    } else {
      key = await _getSharedSecret(otherUserId);
    }
    return _encryptBytesWithSecret(
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
    if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(payload)) {
      return payload;
    }

    try {
      final key = await _resolveMessageKey(
        otherUserId,
        ratchetIndex: ratchetIndex,
        senderIsMe: senderIsMe,
        prev: false,
      );
      // _resolveMessageKey only returns null on the prev path; the
      // current path always resolves (or throws) via _getSharedSecret.
      final decrypted = await _decryptBytesWithSecret(payload, key!);
      return utf8.decode(decrypted);
    } catch (error) {
      // Identity key rotation fallback: in the grace window after
      // [rotateIdentityKeypair] some messages may still be encrypted
      // to the previous keypair. Retry decryption with the prev
      // shared secret; if that succeeds we surface a warning so the
      // operator can see how often the fallback path fires.
      try {
        final prevKey = await _resolveMessageKey(
          otherUserId,
          ratchetIndex: ratchetIndex,
          senderIsMe: senderIsMe,
          prev: true,
        );
        if (prevKey == null) {
          debugPrint('[FIX:local-only] decryptMessage failed: $error');
          return payload;
        }
        final decrypted = await _decryptBytesWithSecret(payload, prevKey);
        debugPrint(
          '[FIX:local-only] decryptMessage fallback to prev identity key '
          'succeeded for $otherUserId',
        );
        return utf8.decode(decrypted);
      } catch (fallbackError) {
        debugPrint(
          '[FIX:local-only] decryptMessage failed (current=$error, '
          'prev-fallback=$fallbackError)',
        );
        return payload;
      }
    }
  }

  /// Resolves the message-level AES-GCM key for [otherUserId].
  ///
  /// When [prev] is `false` the key is derived from the current
  /// identity keypair (the normal path). When `true` the prev
  /// keypair is used instead — returns `null` if no usable prev
  /// keypair is available, which the caller treats as "no fallback".
  Future<SecretKey?> _resolveMessageKey(
    String otherUserId, {
    required int? ratchetIndex,
    required bool senderIsMe,
    required bool prev,
  }) async {
    final sharedSecret = prev
        ? await _getPrevSharedSecret(otherUserId)
        : await _getSharedSecret(otherUserId);
    if (sharedSecret == null) {
      return null;
    }
    if (ratchetIndex == null) {
      return sharedSecret;
    }
    final myId = (await getUserId())!;
    final chains =
        await _ratchet.initializeChains(sharedSecret, myId, otherUserId);
    final chainKey =
        senderIsMe ? chains['mySendChain']! : chains['theirSendChain']!;
    return _ratchet.getNthMessageKey(chainKey, ratchetIndex);
  }

  Future<Map<String, dynamic>> decryptRawMessage(
    Map<String, dynamic> row,
  ) async {
    final message = Map<String, dynamic>.from(row);
    if (message['deleted_at'] != null) {
      return message;
    }

    final metadata =
        message['metadata'] as Map<String, dynamic>? ?? const {};
    final encryption = metadata['encryption'] as String?;
    final ratchetIndex = metadata['sender_ratchet_index'] as int?;
    final senderId = message['sender_id'] as String?;
    final me = await getUserId();

    try {
      if (encryption == 'group_e2e') {
        message['content'] = await _decryptGroupMessage(
          message['chat_id'] as String,
          message['content'] as String,
        );
      } else {
        final otherUserId =
            senderId == me ? await _getOtherUserId(message['chat_id'] as String) : senderId;
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
      debugPrint('[FIX:local-only] decryptRawMessage failed: $error');
    }
    return message;
  }

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
    return _encryptBytesWithSecret(Uint8List.fromList(utf8.encode(content)), key);
  }

  Future<String> _decryptGroupMessage(String chatId, String payload) async {
    final key = await _loadOrCreateGroupSecretKey(chatId);
    final bytes = await _decryptBytesWithSecret(payload, key);
    return utf8.decode(bytes);
  }

  Future<String?> getUserId() => _storage.read('userId');

  Future<String?> getNickname() => _storage.read('nickname');

  Future<void> updateNickname(String nickname) async {
    await _storage.write('nickname', nickname);
    final userId = await getUserId();
    if (userId != null) {
      _nicknameCache[userId] = nickname;
    }
  }

  Future<void> registerUser(String nickname) async {
    final userId = _uuid.v4();
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    await _storage.write('userId', userId);
    await _storage.write('nickname', nickname);
    await _storage.write('privateKey', base64Encode(privateKey));
    await _storage.write('publicKey', base64Encode(publicKey.bytes));
    await _storage.write('registeredAt', DateTime.now().toIso8601String());
    debugPrint('[FIX:local-only] registered local identity userId=$userId');
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _sharedSecretCache.clear();
    _groupSecretCache.clear();
    _nicknameCache.clear();
  }

  Future<String> generateQRCode() async {
    final userId = await getUserId();
    final nickname = await getNickname();
    final publicKey = await _storage.read('publicKey');
    if (userId == null || publicKey == null) {
      return '';
    }
    return _encodeContactBundle({
      'user_id': userId,
      'name': nickname ?? userId,
      'public_key': publicKey,
    });
  }

  String _encodeContactBundle(Map<String, dynamic> contact) {
    final json = jsonEncode({
      'v': 1,
      'user_id': contact['user_id'],
      'name': contact['name'],
      'public_key': contact['public_key'],
    });
    return 'stealth:${base64UrlEncode(utf8.encode(json))}';
  }

  String _normalizeBase64Url(String value) {
    final remainder = value.length % 4;
    return remainder == 0
        ? value
        : value.padRight(value.length + 4 - remainder, '=');
  }

  Map<String, dynamic>? _decodeContactBundle(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('stealth:')) return null;
    try {
      final encoded = trimmed.substring('stealth:'.length);
      final decoded = utf8.decode(base64Url.decode(_normalizeBase64Url(encoded)));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final userId = data['user_id']?.toString();
      final publicKey = data['public_key']?.toString();
      if (userId == null || userId.isEmpty || publicKey == null || publicKey.isEmpty) {
        return null;
      }
      return {
        'user_id': userId,
        'contact_user_id': userId,
        'name': data['name']?.toString() ?? userId,
        'nickname': data['name']?.toString() ?? userId,
        'public_key': publicKey,
      };
    } catch (error) {
      debugPrint('[FIX:local-only] invalid contact bundle: $error');
      return null;
    }
  }

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
    debugPrint('[FIX:local-only] created private chat chatId=$chatId');
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

  Future<void> sendMessage({
    required String chatId,
    required String content,
    required String type,
    String? replyToId,
    Map<String, dynamic>? metadataOverride,
  }) async {
    final me = await getUserId();
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

    String encryptedContent;
    try {
      encryptedContent = isGroupChat
          ? await _encryptGroupMessage(chatId, content)
          : await encryptMessage(
              content,
              otherUserId!,
              ratchetIndex: ratchetIndex,
            );
    } catch (error) {
      debugPrint('[FIX:local-only] sendMessage encryption blocked: $error');
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

    await _localDb.saveMessage(messageMap, synced: true);
    final chat = await _localDb.getChatById(chatId);
    if (chat != null) {
      chat['updated_at'] = now;
      await _localDb.saveChat(chat);
    }

    if (!isGroupChat) {
      final prefs = await SharedPreferences.getInstance();
      final useP2P = prefs.getBool('useP2P') ?? true;
      if (useP2P) {
        await P2PService.instance.sendP2PMessage(chatId, messageMap);
      }
    }
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
    final me = await getUserId();
    final isGroupChat = await _isGroupChat(chatId);
    final otherUserId = isGroupChat ? null : await _getOtherUserId(chatId);
    if (!isGroupChat && (otherUserId == null || otherUserId.isEmpty)) {
      return;
    }
    final encrypted = isGroupChat
        ? await _encryptGroupMessage(chatId, content)
        : await encryptMessage(content, otherUserId!);
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

  Future<String?> uploadAttachmentBytes({
    required Uint8List bytes,
    required String fileName,
    required String chatId,
    bool encrypt = true,
    bool? isGroupChat,
  }) async {
    final groupChat = isGroupChat ?? await _isGroupChat(chatId);
    final otherUserId = groupChat ? null : await _getOtherUserId(chatId);
    if (!groupChat && (otherUserId == null || otherUserId.isEmpty)) {
      return null;
    }
    final key = groupChat
        ? await _loadOrCreateGroupSecretKey(chatId)
        : await _getSharedSecret(otherUserId!);
    if (!encrypt) {
      debugPrint('[FIX:local-only] attachments are stored encrypted; encrypt=false ignored');
    }
    final encryptedPayload = await _encryptBytesWithSecret(bytes, key);
    final descriptor = {
      'v': 1,
      'fileName': fileName,
      'chatId': chatId,
      'isGroupChat': groupChat,
      'encrypted': encrypt,
      'payload': encryptedPayload,
    };
    return 'local-attachment:${base64UrlEncode(utf8.encode(jsonEncode(descriptor)))}';
  }

  Future<Uint8List?> downloadAttachment(
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
      final payload = data['payload'] as String;
      final descriptorEncrypted = data['encrypted'] as bool? ?? encrypted;
      if (!descriptorEncrypted) {
        return Uint8List.fromList(base64Decode(payload));
      }
      final groupChat = isGroupChat ?? (data['isGroupChat'] as bool? ?? await _isGroupChat(chatId));
      final key = groupChat
          ? await _loadOrCreateGroupSecretKey(chatId)
          : await _getSharedSecret((await _getOtherUserId(chatId))!);
      return _decryptBytesWithSecret(payload, key);
    } catch (error) {
      debugPrint('[FIX:local-only] downloadAttachment failed: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>> getStorageDebugSummary() async {
    final messages = <Map<String, dynamic>>[];
    for (final chat in await _localDb.getChats()) {
      messages.addAll(await _localDb.getMessages(chat['id'].toString()));
    }
    final attachmentCount = messages
        .where((message) => message['content']?.toString().startsWith('local-attachment:') ?? false)
        .length;
    return {
      'localMediaReady': true,
      'bucketReady': true,
      'fileCount': attachmentCount,
      'bucketName': 'local encrypted storage',
    };
  }

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

  Future<List<dynamic>> getContacts() async {
    final contacts = await _localDb.getContacts();
    return contacts.map((contact) {
      final copy = Map<String, dynamic>.from(contact);
      copy['user_id'] ??= copy['contact_user_id'];
      copy['name'] ??= copy['nickname'] ?? copy['user_id'];
      return copy;
    }).toList();
  }

  Future<void> deleteContact(String userId) => _localDb.deleteContact(userId);

  Future<void> getNicknames(Set<String> userIds) async {
    for (final id in userIds) {
      _nicknameCache[id] = await getNicknameForUser(id);
    }
  }

  Future<String?> getNicknameForUser(String userId) async {
    if (_nicknameCache.containsKey(userId)) {
      return _nicknameCache[userId];
    }
    final me = await getUserId();
    if (userId == me) {
      final nickname = await getNickname();
      _nicknameCache[userId] = nickname;
      return nickname;
    }
    for (final contact in await _localDb.getContacts()) {
      final id = (contact['contact_user_id'] ?? contact['user_id'])?.toString();
      if (id == userId) {
        final nickname =
            (contact['nickname'] ?? contact['name'] ?? userId).toString();
        _nicknameCache[userId] = nickname;
        return nickname;
      }
    }
    return null;
  }

  Future<String?> getUserNicknameById(String userId) => getNicknameForUser(userId);

  Future<String?> getUserNickname() => getNickname();

  Future<String?> getSafetyNumber(String otherUserId) async {
    final ownPublic = await _storage.read('publicKey');
    late final String otherPublic;
    try {
      final key = await _getOtherPublicKey(otherUserId);
      otherPublic = base64Encode(key.bytes);
    } catch (_) {
      return null;
    }
    if (ownPublic == null || ownPublic.isEmpty || otherPublic.isEmpty) {
      return null;
    }
    final bytes = utf8.encode('$ownPublic:$otherPublic');
    final hash = await Sha256().hash(bytes);
    return base64Encode(hash.bytes).replaceAll('=', '').substring(0, 32);
  }

  /// Returns `true` only when the contact has been user-verified
  /// **and** the snapshot fingerprint still matches the current
  /// derived one. A mismatch (returns `false` even when
  /// `verified_at` is set) means either party's key has rotated
  /// since verification; the UI must show a warning and prompt
  /// re-verification — see [detectSafetyMismatch].
  Future<bool> isContactVerified(String otherUserId) async {
    final contact = await _localDb.getContact(otherUserId);
    if (contact == null) {
      return false;
    }
    final verifiedAt = contact['verified_at']?.toString();
    final storedSafetyNumber = contact['verified_safety_number']?.toString();
    if (verifiedAt == null ||
        verifiedAt.isEmpty ||
        storedSafetyNumber == null ||
        storedSafetyNumber.isEmpty) {
      return false;
    }
    final currentSafetyNumber = await getSafetyNumber(otherUserId);
    if (currentSafetyNumber == null) {
      return false;
    }
    return currentSafetyNumber == storedSafetyNumber;
  }

  /// Records the user's confirmation that the safety number for
  /// [otherUserId] was compared out-of-band and matches. The current
  /// fingerprint is snapshotted into the contact record together with
  /// the wall-clock timestamp.
  ///
  /// Throws [StateError] if the contact is unknown or the safety
  /// number cannot be derived (missing public key on either side).
  Future<void> verifyContact(String otherUserId) async {
    final safetyNumber = await getSafetyNumber(otherUserId);
    if (safetyNumber == null) {
      throw StateError(
        'Cannot verify contact $otherUserId: safety number unavailable. '
        'Likely the contact bundle is missing the peer public key.',
      );
    }
    await _localDb.markContactVerified(
      otherUserId,
      safetyNumber: safetyNumber,
      verifiedAt: DateTime.now(),
    );
    debugPrint(
      '[FIX:local-only] contact verified userId=$otherUserId safety='
      '${safetyNumber.substring(0, 6)}…',
    );
  }

  /// Detects a stale verification: returns a [SafetyNumberMismatch]
  /// when [verifyContact] was called earlier but the current
  /// fingerprint no longer matches the stored snapshot.
  ///
  /// Returns `null` for the happy path (never verified, currently
  /// verified, or contact unknown). The UI calls this on each contact
  /// row to decide between the verified ✓ and the mismatch ⚠ icons.
  Future<SafetyNumberMismatch?> detectSafetyMismatch(
    String otherUserId,
  ) async {
    final contact = await _localDb.getContact(otherUserId);
    if (contact == null) {
      return null;
    }
    final storedSafetyNumber =
        contact['verified_safety_number']?.toString();
    final verifiedAtIso = contact['verified_at']?.toString();
    if (storedSafetyNumber == null ||
        storedSafetyNumber.isEmpty ||
        verifiedAtIso == null ||
        verifiedAtIso.isEmpty) {
      // Either never verified, or the snapshot was cleared (e.g. by
      // a self-rotation reset). No mismatch to surface either way.
      return null;
    }
    final currentSafetyNumber = await getSafetyNumber(otherUserId);
    if (currentSafetyNumber == null ||
        currentSafetyNumber == storedSafetyNumber) {
      return null;
    }
    return SafetyNumberMismatch(
      contactUserId: otherUserId,
      previousSafetyNumber: storedSafetyNumber,
      currentSafetyNumber: currentSafetyNumber,
      previouslyVerifiedAt: DateTime.tryParse(verifiedAtIso),
    );
  }

  /// Rotates the local X25519 identity keypair.
  ///
  /// The current keypair is moved into the `*_prev` slots in secure
  /// storage together with `prev_rotated_at` (wall-clock ISO-8601
  /// timestamp). A fresh keypair is generated and written to the
  /// canonical `privateKey`/`publicKey` slots. All cached shared
  /// secrets are dropped so the next encryption/decryption uses the
  /// new key.
  ///
  /// Every existing contact's `verified_at` is also cleared because
  /// the local public key just changed, which means every safety
  /// number is now different and must be re-verified. The historical
  /// `verified_safety_number` snapshot is left in place so the UI
  /// can show "was previously verified" provenance if needed.
  ///
  /// Returns a [IdentityRotationResult] with the old and new public
  /// keys (base64) plus the expiry of the prev-key grace window.
  Future<IdentityRotationResult> rotateIdentityKeypair() async {
    final prevPriv = await _storage.read('privateKey');
    final prevPub = await _storage.read('publicKey');
    if (prevPriv == null ||
        prevPriv.isEmpty ||
        prevPub == null ||
        prevPub.isEmpty) {
      throw StateError(
        'Cannot rotate identity keypair: no existing keypair to rotate. '
        'Register the user first.',
      );
    }

    final newKeyPair = await _algorithm.newKeyPair();
    final newPublicKey = await newKeyPair.extractPublicKey();
    final newPrivateBytes = await newKeyPair.extractPrivateKeyBytes();
    final rotatedAt = DateTime.now();

    // Persist the previous keypair before overwriting so that an
    // interrupted rotation never loses both halves at once.
    await _storage.write('privateKey_prev', prevPriv);
    await _storage.write('publicKey_prev', prevPub);
    await _storage.write(
      'prev_rotated_at',
      rotatedAt.toIso8601String(),
    );

    await _storage.write('privateKey', base64Encode(newPrivateBytes));
    await _storage.write(
      'publicKey',
      base64Encode(newPublicKey.bytes),
    );

    _sharedSecretCache.clear();
    _prevSharedSecretCache.clear();

    // Every contact's stored safety-number snapshot is now stale —
    // clear the verification timestamp on all of them so the UI
    // shows ⚠ until the user re-verifies.
    await _localDb.clearAllContactsVerifiedAt();

    final result = IdentityRotationResult(
      previousPublicKey: prevPub,
      newPublicKey: base64Encode(newPublicKey.bytes),
      previousKeyExpiresAt: rotatedAt.add(kPrevKeyGracePeriod),
    );
    debugPrint(
      '[FIX:local-only] rotated identity keypair; prev kept until '
      '${result.previousKeyExpiresAt.toIso8601String()}',
    );
    return result;
  }

  /// Best-effort cleanup of an expired prev identity keypair. Safe
  /// to call on every bootstrap — no-op when the prev slot is empty
  /// or still inside the grace window.
  Future<void> pruneExpiredPrevIdentityKey() => _prunePrevKeyIfExpired();

  Future<void> addContact(String userId) async {
    final cached = _lastSearchResults[userId];
    if (cached == null || (cached['public_key']?.toString().isNotEmpty != true)) {
      debugPrint(
        '[FIX:local-only] contact add blocked: missing contact bundle/public key for $userId',
      );
      return;
    }
    final now = DateTime.now().toIso8601String();
    final contact = {
      'contact_user_id': userId,
      'user_id': userId,
      'name': cached['name'] ?? userId,
      'nickname': cached['nickname'] ?? cached['name'] ?? userId,
      'public_key': cached['public_key'],
      'created_at': now,
    };
    await _localDb.saveContact(contact);
    _nicknameCache[userId] = contact['nickname']?.toString();
    debugPrint('[FIX:local-only] saved local contact userId=$userId');
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final bundle = _decodeContactBundle(trimmed);
    if (bundle != null) {
      _lastSearchResults[bundle['user_id'] as String] = bundle;
      return [bundle];
    }

    final results = <Map<String, dynamic>>[];
    final me = await getUserId();
    final nickname = await getNickname();
    final publicKey = await _storage.read('publicKey');
    if (me != null &&
        (me == trimmed || (nickname ?? '').toLowerCase().contains(trimmed.toLowerCase()))) {
      final self = {
        'user_id': me,
        'contact_user_id': me,
        'name': nickname ?? me,
        'nickname': nickname ?? me,
        'public_key': publicKey ?? '',
      };
      _lastSearchResults[me] = self;
      results.add(self);
    }

    for (final contact in await getContacts()) {
      final id = contact['user_id']?.toString() ?? '';
      final name = contact['name']?.toString() ?? '';
      if (id == trimmed || name.toLowerCase().contains(trimmed.toLowerCase())) {
        final row = Map<String, dynamic>.from(contact as Map);
        _lastSearchResults[id] = row;
        results.add(row);
      }
    }

    return results;
  }

  Future<void> markChatRead(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    chat['last_read_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }

  Future<void> setTypingStatus({
    required String chatId,
    required bool isTyping,
  }) async {
    debugPrint('[FIX:local-only] typing status local-only chatId=$chatId isTyping=$isTyping');
  }

  Future<DateTime?> getOtherLastReadAt(String chatId) async => null;

  void subscribeP2PSignaling(String chatId) {
    unawaited(P2PService.instance.subscribeSignaling(chatId));
  }

  Future<void> recordIncomingCall({
    required String chatId,
    required String fromUserId,
    required String fromNickname,
  }) async {
    await _localDb.saveCall({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'direction': 'incoming',
      'status': 'initiated',
      'peer_user_id': fromUserId,
      'peer_nickname': fromNickname,
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> markIncomingCallDeclined({
    required String chatId,
    required String fromUserId,
  }) async {
    await _localDb.saveCall({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'direction': 'incoming',
      'status': 'declined',
      'peer_user_id': fromUserId,
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> markCurrentUserCallEnded({required String chatId}) async {
    await _localDb.saveCall({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'direction': 'local',
      'status': 'ended',
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getRecentCallHistory({int limit = 5}) async {
    final calls = await _localDb.getCalls();
    calls.sort(
      (a, b) => (b['started_at']?.toString() ?? '')
          .compareTo(a['started_at']?.toString() ?? ''),
    );
    return calls.take(limit).toList();
  }
}

/// Result of [LocalAppService.rotateIdentityKeypair].
class IdentityRotationResult {
  const IdentityRotationResult({
    required this.previousPublicKey,
    required this.newPublicKey,
    required this.previousKeyExpiresAt,
  });

  /// Public key (base64, X25519) that was active before rotation.
  final String previousPublicKey;

  /// Public key (base64, X25519) generated by this rotation.
  final String newPublicKey;

  /// Wall-clock time at which the previous keypair will be pruned
  /// from secure storage and can no longer be used as a decryption
  /// fallback. Equal to `now + LocalAppService.kPrevKeyGracePeriod`.
  final DateTime previousKeyExpiresAt;
}

/// Result of [LocalAppService.detectSafetyMismatch].
///
/// Carries the values needed to render a "the safety number has
/// changed since you verified this contact" warning — both
/// fingerprints plus the wall-clock time of the original
/// verification.
class SafetyNumberMismatch {
  const SafetyNumberMismatch({
    required this.contactUserId,
    required this.previousSafetyNumber,
    required this.currentSafetyNumber,
    required this.previouslyVerifiedAt,
  });

  final String contactUserId;
  final String previousSafetyNumber;
  final String currentSafetyNumber;
  final DateTime? previouslyVerifiedAt;
}
