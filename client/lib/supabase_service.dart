import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:stealth/crypto/ratchet_service.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/p2p_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'storage_service.dart';

class SupabaseService {
  static const String _attachmentsBucket = 'chat-media';

  /// Глобальный broadcast для событий `call_accept`. Нужен, чтобы активный
  /// `WebRTCCallScreen` у вызывающей стороны мог узнать о принятии звонка и
  /// отправить offer уже после того, как принимающий клиент гарантированно
  /// подписан на `chat_calls` канал. Без этого offer отправлялся до того, как
  /// принимающая сторона успевала подписаться, и сигналинг терялся.
  static final StreamController<Map<String, dynamic>> _callAcceptedController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get callAcceptedStream =>
      _callAcceptedController.stream;

  final SupabaseClient supabase = Supabase.instance.client;
  final StorageService _storage = StorageService();
  final RatchetService _ratchet = RatchetService();
  final Uuid _uuid = const Uuid();
  final Map<String, String?> _nicknameCache = {};
  final X25519 _algorithm = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Map<String, SecretKey> _sharedSecretCache = {};
  final LocalDatabaseService _localDb = LocalDatabaseService();

  /// Экранирует спецсимволы ILIKE для защиты от SQL-инъекций.
  static String _escapeIlike(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  static bool _looksLikeUuid(String input) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(input);
  }

  final Map<String, SecretKey> _groupSecretCache = {};
  RealtimeChannel? _userCallsChannel;
  RealtimeChannel? _chatCallsChannel;

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

  Future<PublicKey> _getOtherPublicKey(String userId) async {
    final response = await supabase
        .from('users')
        .select('public_key')
        .eq('id', userId)
        .single();
    return SimplePublicKey(
      base64Decode(response['public_key'] as String),
      type: KeyPairType.x25519,
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

  Future<String> encryptMessage(String content, String otherUserId,
      {int? ratchetIndex}) async {
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
        Uint8List.fromList(utf8.encode(content)), key);
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
        final myId = (await getUserId())!;
        final sharedSecret = await _getSharedSecret(otherUserId);
        final chains =
            await _ratchet.initializeChains(sharedSecret, myId, otherUserId);
        // If the message was sent by me, its key came from `mySendChain`.
        // Otherwise it's encrypted with the peer's send chain which for us is `theirSendChain`.
        final chainKey =
            senderIsMe ? chains['mySendChain']! : chains['theirSendChain']!;
        key = await _ratchet.getNthMessageKey(chainKey, ratchetIndex);
      } else {
        key = await _getSharedSecret(otherUserId);
      }

      final combined = base64Decode(payload);
      if (combined.length < 28) {
        return payload;
      }
      final clearText = await _decryptBytesWithSecret(payload, key);
      return utf8.decode(clearText);
    } catch (error) {
      debugPrint('Decryption error: $error');
      return payload;
    }
  }

  Future<List<String>> _getChatMemberIds(String chatId) async {
    final rows = await supabase
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId);
    return rows.map<String>((row) => row['user_id'] as String).toList();
  }

  /// Расшифровывает одно сообщение из сырого ряда БД, учитывая тип шифрования
  /// (групповое или парное) и роль отправителя. Безопасен для realtime-потока.
  Future<Map<String, dynamic>> decryptRawMessage(
    Map<String, dynamic> row,
  ) async {
    final result = Map<String, dynamic>.from(row);
    final chatId = result['chat_id'] as String?;
    if (chatId == null) {
      return result;
    }
    final content = result['content'];
    if (content is! String || content.isEmpty) {
      return result;
    }
    final metadata = result['metadata'] as Map<String, dynamic>? ?? const {};
    final encryption = metadata['encryption'] as String?;
    final ratchetIndex = metadata['sender_ratchet_index'] as int?;
    final senderId = result['sender_id'] as String?;
    final me = await getUserId();
    try {
      if (encryption == 'group_e2e') {
        result['content'] = await _decryptGroupMessage(chatId, content);
      } else {
        final otherUserId = await _getOtherUserId(chatId);
        if (otherUserId != null && otherUserId.isNotEmpty) {
          result['content'] = await decryptMessage(
            content,
            otherUserId,
            ratchetIndex: ratchetIndex,
            senderIsMe: me != null && senderId == me,
          );
        }
      }
    } catch (error) {
      debugPrint('decryptRawMessage error: $error');
    }
    return result;
  }

  Future<SecretKey> _loadOrCreateGroupSecretKey(String chatId) async {
    if (_groupSecretCache.containsKey(chatId)) {
      return _groupSecretCache[chatId]!;
    }

    final me = await getUserId();
    if (me == null) {
      throw Exception('User not authenticated');
    }

    final existingEnvelope = await supabase
        .from('group_key_envelopes')
        .select('encrypted_key, wrapped_by_user_id')
        .eq('chat_id', chatId)
        .eq('user_id', me)
        .maybeSingle();

    if (existingEnvelope != null) {
      final encryptedKey = existingEnvelope['encrypted_key'] as String;
      final wrappedByUserId = existingEnvelope['wrapped_by_user_id'] as String;
      final envelopeSecret = await _getSharedSecret(wrappedByUserId);
      final rawKey =
          await _decryptBytesWithSecret(encryptedKey, envelopeSecret);
      final groupKey = SecretKey(rawKey);
      _groupSecretCache[chatId] = groupKey;
      return groupKey;
    }

    await rekeyGroupChat(chatId);
    return _groupSecretCache[chatId]!;
  }

  Future<void> rekeyGroupChat(String chatId) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    final members = await _getChatMemberIds(chatId);
    if (members.length < 3) {
      _groupSecretCache.remove(chatId);
      return;
    }

    final generatedKey = await _aes.newSecretKey();
    final rawKey = await generatedKey.extractBytes();
    final envelopes = <Map<String, dynamic>>[];
    for (final memberId in members) {
      final memberSecret = await _getSharedSecret(memberId);
      final encryptedKey = await _encryptBytesWithSecret(
        Uint8List.fromList(rawKey),
        memberSecret,
      );
      envelopes.add({
        'chat_id': chatId,
        'user_id': memberId,
        'wrapped_by_user_id': me,
        'encrypted_key': encryptedKey,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
    await supabase.from('group_key_envelopes').upsert(envelopes);
    _groupSecretCache[chatId] = generatedKey;
  }

  Future<String> _encryptGroupMessage(String chatId, String content) async {
    final groupSecret = await _loadOrCreateGroupSecretKey(chatId);
    return _encryptBytesWithSecret(
      Uint8List.fromList(utf8.encode(content)),
      groupSecret,
    );
  }

  Future<String> _decryptGroupMessage(String chatId, String payload) async {
    try {
      if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(payload)) {
        return payload;
      }
      final groupSecret = await _loadOrCreateGroupSecretKey(chatId);
      final clearText = await _decryptBytesWithSecret(payload, groupSecret);
      return utf8.decode(clearText);
    } catch (error) {
      debugPrint('Group decryption error: $error');
      return payload;
    }
  }

  Future<String?> getUserId() => _storage.read('userId');
  Future<String?> getNickname() => _storage.read('nickname');
  Future<String?> getPrivateKey() => _storage.read('privateKey');

  Future<void> updateNickname(String nickname) async {
    final userId = await getUserId();
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    await supabase.from('users').update({
      'nickname': nickname,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);

    await _storage.write('nickname', nickname);
    _nicknameCache[userId] = nickname;
  }

  Future<void> registerUser(String nickname) async {
    // Авторизация через Supabase Auth для поддержки Row Level Security (RLS)
    final authResponse = await supabase.auth.signInAnonymously();
    final user = authResponse.user;
    if (user == null) {
      throw Exception('Failed to sign in anonymously');
    }
    final userId = user.id;

    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    await _storage.write('userId', userId);
    await _storage.write('nickname', nickname);
    await _storage.write('privateKey', base64Encode(privateKey));
    await _storage.write('publicKey', base64Encode(publicKey.bytes));

    await supabase.from('users').insert({
      'id': userId,
      'nickname': nickname,
      'public_key': base64Encode(publicKey.bytes),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    await _storage.deleteAll();
    _nicknameCache.clear();
    _sharedSecretCache.clear();
    _groupSecretCache.clear();
  }

  Future<String?> findOrCreatePrivateChatWith(String otherUserId) async {
    final me = await getUserId();
    if (me == null) {
      return null;
    }

    try {
      final existingChats = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', me)
          .timeout(const Duration(seconds: 5));
      for (final row in existingChats) {
        final chatId = row['chat_id'] as String;
        final otherUserInChat = await supabase
            .from('chat_members')
            .select('user_id')
            .eq('chat_id', chatId)
            .eq('user_id', otherUserId)
            .maybeSingle()
            .timeout(const Duration(seconds: 3));
        if (otherUserInChat != null) {
          return chatId;
        }
      }

      final chatId = _uuid.v4();
      final chatData = {
        'id': chatId,
        'name': '',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'members': [me, otherUserId],
      };
      await supabase.from('chats').insert({
        'id': chatData['id'],
        'name': chatData['name'],
        'created_at': chatData['created_at'],
        'updated_at': chatData['updated_at'],
      }).timeout(const Duration(seconds: 5));
      await supabase.from('chat_members').insert([
        {'chat_id': chatId, 'user_id': me},
        {'chat_id': chatId, 'user_id': otherUserId},
      ]).timeout(const Duration(seconds: 5));

      // Cache locally
      await _localDb.saveChat(chatData);

      return chatId;
    } catch (error) {
      debugPrint('Error finding or creating chat: $error');
      return null;
    }
  }

  Future<String?> createGroupChat({
    required String name,
    required List<String> memberIds,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return null;
    }

    final uniqueMembers =
        {me, ...memberIds.where((id) => id.trim().isNotEmpty)}.toList();
    if (uniqueMembers.length < 3) {
      throw Exception('A group chat requires at least 3 members.');
    }

    try {
      final chatId = _uuid.v4();
      final chatData = {
        'id': chatId,
        'name': name.trim().isEmpty ? 'New group' : name.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'members': uniqueMembers,
      };

      await supabase.from('chats').insert({
        'id': chatData['id'],
        'name': chatData['name'],
        'created_at': chatData['created_at'],
        'updated_at': chatData['updated_at'],
      });

      await supabase.from('chat_members').insert(
            uniqueMembers.map((userId) {
              return {
                'chat_id': chatId,
                'user_id': userId,
                'role': userId == me ? 'admin' : 'member',
              };
            }).toList(),
          );
      await rekeyGroupChat(chatId);

      // Cache locally
      await _localDb.saveChat(chatData);

      return chatId;
    } catch (error) {
      debugPrint('Error creating group chat: $error');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getChatMembers(String chatId) async {
    final rows = await supabase
        .from('chat_members')
        .select('user_id, role')
        .eq('chat_id', chatId);
    final members = <Map<String, dynamic>>[];
    for (final row in rows) {
      final userId = row['user_id'] as String;
      members.add({
        'user_id': userId,
        'name': await getNicknameForUser(userId) ?? 'Unknown',
        'role': row['role'] as String? ?? 'member',
      });
    }
    return members;
  }

  Future<String?> getMyRoleInChat(String chatId) async {
    final me = await getUserId();
    if (me == null) {
      return null;
    }

    final row = await supabase
        .from('chat_members')
        .select('role')
        .eq('chat_id', chatId)
        .eq('user_id', me)
        .maybeSingle();
    return row?['role'] as String?;
  }

  Future<void> _ensureAdminRole(String chatId) async {
    final role = await getMyRoleInChat(chatId);
    if (role != 'admin') {
      throw Exception('Admin role required for this action.');
    }
  }

  Future<int> _countAdminsInChat(String chatId) async {
    return await supabase
        .from('chat_members')
        .count(CountOption.exact)
        .eq('chat_id', chatId)
        .eq('role', 'admin');
  }

  Future<void> addMembersToGroupChat({
    required String chatId,
    required List<String> memberIds,
  }) async {
    if (memberIds.isEmpty) {
      return;
    }

    await _ensureAdminRole(chatId);
    await supabase.from('chat_members').upsert(
          memberIds
              .map((userId) => {
                    'chat_id': chatId,
                    'user_id': userId,
                    'role': 'member',
                  })
              .toList(),
        );
    await rekeyGroupChat(chatId);
  }

  Future<void> removeMemberFromGroupChat({
    required String chatId,
    required String memberId,
  }) async {
    await _ensureAdminRole(chatId);
    final adminCount = await _countAdminsInChat(chatId);
    final memberRole = await supabase
        .from('chat_members')
        .select('role')
        .eq('chat_id', chatId)
        .eq('user_id', memberId)
        .maybeSingle();
    final role = memberRole?['role'] as String?;
    if (role == 'admin' && adminCount <= 1) {
      throw Exception('Group must keep at least one admin.');
    }

    await supabase
        .from('chat_members')
        .delete()
        .eq('chat_id', chatId)
        .eq('user_id', memberId);
    await supabase
        .from('group_key_envelopes')
        .delete()
        .eq('chat_id', chatId)
        .eq('user_id', memberId);
    await rekeyGroupChat(chatId);
  }

  Future<void> updateGroupMemberRole({
    required String chatId,
    required String memberId,
    required String role,
  }) async {
    await _ensureAdminRole(chatId);
    final me = await getUserId();
    if (me == null) {
      return;
    }
    if (role == 'member' && memberId == me) {
      final adminCount = await _countAdminsInChat(chatId);
      if (adminCount <= 1) {
        throw Exception('Group must keep at least one admin.');
      }
    }

    await supabase
        .from('chat_members')
        .update({'role': role})
        .eq('chat_id', chatId)
        .eq('user_id', memberId);
  }

  Future<List<dynamic>> getChats() async {
    final me = await getUserId();
    if (me == null) {
      return [];
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final useSupabase = prefs.getBool('useSupabase') ?? true;
      if (!useSupabase) {
        return await _localDb.getChats();
      }

      final membership = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', me)
          .timeout(const Duration(seconds: 5));
      if (membership.isEmpty) {
        return [];
      }

      final chatIds =
          membership.map<String>((row) => row['chat_id'] as String).toList();
      final chatsResponse = await supabase
          .from('chats')
          .select('id, name, created_at, updated_at, chat_members(user_id)')
          .inFilter('id', chatIds)
          .order('updated_at', ascending: false)
          .timeout(const Duration(seconds: 5));

      final result = chatsResponse.map((chat) {
        final members = (chat['chat_members'] as List<dynamic>? ?? [])
            .map<String>((member) => member['user_id'] as String)
            .toList();
        // Older live schemas do not expose chats.is_private, so infer it from
        // the participant count and group naming convention.
        final isPrivate = members.length <= 2;
        return {
          'id': chat['id'],
          'name': chat['name'],
          'is_private': isPrivate,
          'created_at': chat['created_at'],
          'updated_at': chat['updated_at'],
          'members': members,
        };
      }).toList();

      // Cache chats locally so offline fallback works
      for (final chat in result) {
        try {
          await _localDb.saveChat(chat);
        } catch (_) {}
      }
      return result;
    } catch (error) {
      debugPrint(
          'Error fetching chats from Supabase, falling back to local: $error');
      // Offline fallback: return cached chats from local DB
      try {
        return await _localDb.getChats();
      } catch (localError) {
        debugPrint('Local DB fallback also failed: $localError');
        return [];
      }
    }
  }

  Future<String?> getNicknameForUser(String userId) async {
    if (_nicknameCache.containsKey(userId)) {
      return _nicknameCache[userId];
    }

    String? nickname;
    try {
      final response = await supabase
          .from('users')
          .select('nickname')
          .eq('id', userId)
          .maybeSingle();
      nickname = response?['nickname'] as String?;
    } catch (_) {
      nickname = null;
    }

    nickname ??= 'User ${userId.substring(0, 4)}';
    _nicknameCache[userId] = nickname;
    return nickname;
  }

  Future<String?> getSafetyNumber(String otherUserId) async {
    final myPubKey = await _storage.read('publicKey');
    if (myPubKey == null) return null;

    final response = await supabase
        .from('users')
        .select('public_key')
        .eq('id', otherUserId)
        .maybeSingle();

    if (response == null || response['public_key'] == null) return null;
    final theirPubKey = response['public_key'] as String;

    final keys = [myPubKey, theirPubKey]..sort();
    final bytes = utf8.encode(keys.join('|'));
    final sha256 = Sha256();
    final hash = await sha256.hash(bytes);

    final digestStr = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    return digestStr
        .replaceAllMapped(RegExp(r'.{4}'), (match) => '${match.group(0)} ')
        .trim();
  }

  Future<List<dynamic>> getMessages(
    String chatId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useSupabase = prefs.getBool('useSupabase') ?? true;

      // 1. Always load from Local DB FIRST for instant UI
      final localMessages = await _localDb.getMessages(chatId);
      
      // If we are offline or useSupabase is false, just return local messages
      if (!useSupabase) {
        return _decryptAndProcessMessages(localMessages, chatId);
      }

      // 2. Fetch latest from Supabase in background to sync local DB
      try {
        final response = await supabase
            .from('messages')
            .select('*')
            .eq('chat_id', chatId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .range(0, limit - 1) 
            .timeout(const Duration(seconds: 5));
        
        final remoteMessages = List.from(response);
        for (final msg in remoteMessages) {
          // Always cache locally — Supabase is backup storage, local DB is primary
          await _localDb.saveMessage(msg, synced: true);
        }
      } catch (e) {
        debugPrint('Supabase fetch failed during local-first sync: $e');
      }

      // 3. Reload from local DB after sync to get the unified list
      final unifiedMessages = await _localDb.getMessages(chatId);
      return _decryptAndProcessMessages(unifiedMessages, chatId);
    } catch (error) {
      debugPrint('Error fetching messages: $error');
      return [];
    }
  }

  Future<List<dynamic>> _decryptAndProcessMessages(List<dynamic> messages, String chatId) async {
    final otherUserId = await _getOtherUserId(chatId);
    final me = await getUserId();

    for (final message in messages) {
      final metadata =
          message['metadata'] as Map<String, dynamic>? ?? const {};
      final encryption = metadata['encryption'] as String?;
      final ratchetIndex = metadata['sender_ratchet_index'] as int?;
      final senderId = message['sender_id'] as String?;

      if (encryption == 'group_e2e') {
        message['content'] = await _decryptGroupMessage(
          chatId,
          message['content'] as String,
        );
      } else if (otherUserId != null && otherUserId.isNotEmpty) {
        message['content'] = await decryptMessage(
          message['content'] as String,
          otherUserId,
          ratchetIndex: ratchetIndex,
          senderIsMe: me != null && senderId == me,
        );
      }
    }
    // Return sorted by creation time
    return messages..sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));
  }

  Future<void> sendMessage({
    required String chatId,
    required String content,
    required String type,
    String? replyToId,
    Map<String, dynamic>? metadataOverride,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    final otherUserId = await _getOtherUserId(chatId);

    try {
      final prefs = await SharedPreferences.getInstance();
      final useSupabase = prefs.getBool('useSupabase') ?? true;
      final isGroupChat = otherUserId == null || otherUserId.isEmpty;

      int? ratchetIndex;
      if (!isGroupChat) {
        if (useSupabase) {
          try {
            // Online: count from Supabase for accurate ratchet state
            ratchetIndex = await supabase
                .from('messages')
                .count(CountOption.exact)
                .eq('chat_id', chatId)
                .eq('sender_id', me)
                .not('metadata->sender_ratchet_index', 'is', 'null')
                .timeout(const Duration(seconds: 3));
          } catch (e) {
            debugPrint(
                'Supabase ratchet count failed, falling back to local: $e');
            // Fallback to local count if Supabase is unreachable
            final localMsgs = await _localDb.getMessages(chatId);
            ratchetIndex = localMsgs
                .where((m) =>
                    m['sender_id'] == me &&
                    (m['metadata'] as Map<String, dynamic>? ?? {})
                        .containsKey('sender_ratchet_index'))
                .length;
          }
        } else {
          // Offline: count from local DB
          final localMsgs = await _localDb.getMessages(chatId);
          ratchetIndex = localMsgs
              .where((m) =>
                  m['sender_id'] == me &&
                  (m['metadata'] as Map<String, dynamic>? ?? {})
                      .containsKey('sender_ratchet_index'))
              .length;
        }
      }

      final encryptedContent = isGroupChat
          ? await _encryptGroupMessage(chatId, content)
          : await encryptMessage(content, otherUserId,
              ratchetIndex: ratchetIndex);

      final metadata = <String, dynamic>{
        'encryption': isGroupChat ? 'group_e2e' : 'e2e',
        if (metadataOverride != null) ...metadataOverride,
      };
      if (ratchetIndex != null) {
        metadata['sender_ratchet_index'] = ratchetIndex;
      }

      final messageMap = {
        'id': _uuid.v4(), // Client-side UUID for reliable tracking
        'chat_id': chatId,
        'sender_id': me,
        'content': encryptedContent,
        'message_type': type,
        'reply_to_id': replyToId,
        'metadata': metadata,
        'created_at': DateTime.now().toIso8601String(),
      };

      // 1. Try P2P Delivery first (Hybrid Delivery)
      bool p2pSent = false;
      try {
        final p2p = P2PService.instance;
        if (p2p.isP2PReady(chatId)) {
          final p2pPayload = Map<String, dynamic>.from(messageMap);
          // Mark as synced for the recipient's local DB upon receipt
          p2pPayload['synced_p2p'] = true;
          p2pSent = await p2p.sendP2PMessage(chatId, p2pPayload);
          if (p2pSent) {
            debugPrint('Message sent via P2P successfully');
          }
        }
      } catch (e) {
        debugPrint('P2P delivery attempt failed: $e');
      }

      // Always save locally FIRST as UN-synced.
      // If we are online and insert succeeds, we will mark it synced immediately after.
      final forceP2P = prefs.getBool('forceP2P') ?? false;
      final localMessageId =
          await _localDb.saveMessage(messageMap, synced: forceP2P);

      if (useSupabase && !forceP2P) {
        try {
          await supabase
              .from('messages')
              .insert(messageMap)
              .timeout(const Duration(seconds: 5));
          await supabase
              .from('chats')
              .update({'updated_at': DateTime.now().toIso8601String()})
              .eq('id', chatId)
              .timeout(const Duration(seconds: 5));

          // Mark as synced since Supabase accepted it
          if (localMessageId != null) {
            await _localDb.markMessageSyncedByLocalKey(localMessageId);
          }
        } catch (e) {
          debugPrint('Supabase insert failed (will sync later): $e');
          // It remains synced: false in local DB, so SyncService will pick it up
        }
      }
    } catch (error) {
      debugPrint('Error sending message: $error');
    }
  }

  Future<void> editMessage({
    required String messageId,
    required String chatId,
    required String content,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    final otherUserId = await _getOtherUserId(chatId);
    final isGroupChat = otherUserId == null || otherUserId.isEmpty;

    final message = await supabase
        .from('messages')
        .select('metadata')
        .eq('id', messageId)
        .single();
    final metadata = message['metadata'] as Map<String, dynamic>? ?? {};
    final ratchetIndex = metadata['sender_ratchet_index'] as int?;

    final encryptedContent = isGroupChat
        ? await _encryptGroupMessage(chatId, content)
        : await encryptMessage(content, otherUserId,
            ratchetIndex: ratchetIndex);

    await supabase
        .from('messages')
        .update({
          'content': encryptedContent,
          'edited_at': DateTime.now().toIso8601String(),
        })
        .eq('id', messageId)
        .eq('sender_id', me);
  }

  Future<void> softDeleteMessage({
    required String messageId,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    await supabase
        .from('messages')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', messageId)
        .eq('sender_id', me);
    await supabase.from('pinned_messages').delete().eq('message_id', messageId);
  }

  Future<void> pinMessage({
    required String chatId,
    required String messageId,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    await supabase.from('pinned_messages').upsert({
      'chat_id': chatId,
      'message_id': messageId,
      'pinned_by_user_id': me,
    });
  }

  Future<void> unpinMessage({
    required String chatId,
    required String messageId,
  }) async {
    await supabase
        .from('pinned_messages')
        .delete()
        .eq('chat_id', chatId)
        .eq('message_id', messageId);
  }

  Future<Map<String, dynamic>?> getPinnedMessage(String chatId) async {
    try {
      final row = await supabase
          .from('pinned_messages')
          .select(
              'message_id, messages(id, content, message_type, metadata, sender_id)')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) {
        return null;
      }

      final message = row['messages'] as Map<String, dynamic>?;
      if (message == null) {
        return null;
      }

      final content = message['content'] as String? ?? '';
      final metadata = message['metadata'] as Map<String, dynamic>? ?? const {};
      final encryption = metadata['encryption'] as String?;
      final ratchetIndex = metadata['sender_ratchet_index'] as int?;
      final senderId = message['sender_id'] as String?;
      final me = await getUserId();
      final otherUserId = await _getOtherUserId(chatId);
      final decodedContent = encryption == 'group_e2e'
          ? await _decryptGroupMessage(chatId, content)
          : (otherUserId == null || otherUserId.isEmpty
              ? content
              : await decryptMessage(
                  content,
                  otherUserId,
                  ratchetIndex: ratchetIndex,
                  senderIsMe: me != null && senderId == me,
                ));

      return {
        'id': message['id'].toString(),
        'content': decodedContent,
        'type': message['message_type'],
      };
    } catch (error) {
      debugPrint('Error loading pinned message: $error');
      return null;
    }
  }

  Future<String?> uploadAttachmentBytes({
    required Uint8List bytes,
    required String fileName,
    required String chatId,
    bool encrypt = false,
  }) async {
    final userId = await getUserId();
    if (userId == null) {
      return null;
    }

    Uint8List dataToUpload = bytes;
    if (encrypt) {
      try {
        final otherUserId = await _getOtherUserId(chatId);
        final isGroupChat = otherUserId == null || otherUserId.isEmpty;
        
        final SecretKey secretKey = isGroupChat
            ? await _loadOrCreateGroupSecretKey(chatId)
            : await _getSharedSecret(otherUserId);

        final encryptedBase64 =
            await _encryptBytesWithSecret(bytes, secretKey);
        dataToUpload = base64Decode(encryptedBase64);
      } catch (e) {
        debugPrint('Error encrypting attachment: $e');
        return null;
      }
    }

    final storagePath =
        '$userId/$chatId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      await supabase.storage
          .from(_attachmentsBucket)
          .uploadBinary(storagePath, dataToUpload);
      return supabase.storage
          .from(_attachmentsBucket)
          .getPublicUrl(storagePath);
    } catch (error) {
      debugPrint('Error uploading attachment bytes: $error');
      return null;
    }
  }

  Future<Uint8List?> downloadAttachment(String url, String chatId,
      {bool encrypted = false}) async {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      // Handle both public and private/authenticated URLs from Supabase
      final bucketIndex = pathSegments.indexOf(_attachmentsBucket);
      if (bucketIndex == -1) {
        debugPrint('Invalid attachment URL: bucket not found in path');
        return null;
      }
      final relativePath = pathSegments.sublist(bucketIndex + 1).join('/');

      final bytes = await supabase.storage
          .from(_attachmentsBucket)
          .download(relativePath);

      if (encrypted) {
        final otherUserId = await _getOtherUserId(chatId);
        final isGroupChat = otherUserId == null || otherUserId.isEmpty;

        final SecretKey secretKey = isGroupChat
            ? await _loadOrCreateGroupSecretKey(chatId)
            : await _getSharedSecret(otherUserId);
        final base64Payload = base64Encode(bytes);
        return await _decryptBytesWithSecret(base64Payload, secretKey);
      }
      return bytes;
    } catch (e) {
      debugPrint('Error downloading attachment: $e');
      return null;
    }
  }

  /// Проверяет наличие бакета для вложений.
  Future<bool> debugHasAttachmentBucket() async {
    try {
      final buckets = await supabase.storage.listBuckets();
      return buckets.any((bucket) => bucket.id == _attachmentsBucket);
    } catch (error) {
      debugPrint('Error checking storage bucket: $error');
      return false;
    }
  }

  /// Возвращает краткую сводку хранилища для текущего пользователя.
  Future<Map<String, dynamic>> getStorageDebugSummary() async {
    final userId = await getUserId();
    if (userId == null) {
      return {
        'bucketReady': false,
        'fileCount': 0,
        'folder': '',
      };
    }

    try {
      final files = await supabase.storage.from(_attachmentsBucket).list(
            path: userId,
          ).timeout(const Duration(seconds: 5));
      return {
        'bucketReady': true,
        'fileCount': files.length,
        'folder': userId,
      };
    } catch (error) {
      debugPrint('Error loading storage summary: $error');
      return {
        'bucketReady': await debugHasAttachmentBucket(),
        'fileCount': 0,
        'folder': userId,
      };
    }
  }

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final me = await getUserId();
    if (me == null) {
      return {
        'chatCount': 0,
        'contactCount': 0,
        'messageCount': 0,
        'callCount': 0,
        'secureStorageReady': false,
        'hasPrivateKey': false,
      };
    }

    try {
      // Local-first calculation for instant response
      final localChats = await _localDb.getChats();
      final localContacts = await _localDb.getContacts();
      final localCalls = await _localDb.getCalls();
      
      var messageCount = 0;
      for (final chat in localChats) {
        final msgs = await _localDb.getMessages(chat['id'] as String);
        messageCount += msgs.length;
      }

      final bucketReady = await debugHasAttachmentBucket();

      return {
        'chatCount': localChats.length,
        'contactCount': localContacts.length,
        'messageCount': messageCount,
        'callCount': localCalls.length,
        'secureStorageReady': true,
        'bucketReady': bucketReady,
      };
    } catch (error) {
      debugPrint('Error loading dashboard summary: $error');
      return {
        'chatCount': 0,
        'contactCount': 0,
        'messageCount': 0,
        'callCount': 0,
        'secureStorageReady': false,
      };
    }
  }

  Future<List<double>> getWeeklyActivityBars() async {
    try {
      final now = DateTime.now().toUtc();
      final start = now.subtract(const Duration(days: 6));

      // Local-first activity calculation
      final localChats = await _localDb.getChats();
      final messageTimestamps = <DateTime>[];
      for (final chat in localChats) {
        final msgs = await _localDb.getMessages(chat['id'] as String);
        for (final m in msgs) {
          final ts = DateTime.tryParse(m['created_at'] as String? ?? '');
          if (ts != null) messageTimestamps.add(ts);
        }
      }

      final localCalls = await _localDb.getCalls();
      final callTimestamps = <DateTime>[];
      for (final c in localCalls) {
        final ts = DateTime.tryParse(c['started_at'] as String? ?? '');
        if (ts != null) callTimestamps.add(ts);
      }

      final buckets = List<int>.filled(7, 0);
      for (final date in messageTimestamps) {
        final diff = now.difference(date.toUtc()).inDays;
        if (diff >= 0 && diff < 7) {
          buckets[6 - diff] += 1;
        }
      }
      for (final date in callTimestamps) {
        final diff = now.difference(date.toUtc()).inDays;
        if (diff >= 0 && diff < 7) {
          buckets[6 - diff] += 1;
        }
      }

      final maxVal = buckets.fold<int>(0, (m, v) => v > m ? v : m);
      if (maxVal == 0) return List<double>.filled(7, 0.12);

      return buckets.map((v) => (v / maxVal).clamp(0.12, 1.0)).toList();
    } catch (error) {
      debugPrint('Error calculating weekly activity: $error');
      return List<double>.filled(7, 0.12);
    }
  }

  Future<Map<String, dynamic>?> fetchLastMessage(String chatId) async {
    try {
      final otherUserId = await _getOtherUserId(chatId);
      final me = await getUserId();
      final response = await supabase
          .from('messages')
          .select('*')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (response != null && response['content'] is String) {
        final metadata =
            response['metadata'] as Map<String, dynamic>? ?? const {};
        final encryption = metadata['encryption'] as String?;
        final ratchetIndex = metadata['sender_ratchet_index'] as int?;
        final senderId = response['sender_id'] as String?;
        if (encryption == 'group_e2e') {
          response['content'] = await _decryptGroupMessage(
            chatId,
            response['content'] as String,
          );
        } else if (otherUserId != null && otherUserId.isNotEmpty) {
          response['content'] = await decryptMessage(
            response['content'] as String,
            otherUserId,
            ratchetIndex: ratchetIndex,
            senderIsMe: me != null && senderId == me,
          );
        }
      }
      return response;
    } catch (error) {
      debugPrint('Error fetching last message: $error');
      return null;
    }
  }

  Future<DateTime?> getLastSeen(String chatId) async {
    try {
      final me = await getUserId();
      if (me == null) {
        return null;
      }

      final response = await supabase
          .from('chat_members')
          .select('last_read_at')
          .eq('chat_id', chatId)
          .eq('user_id', me)
          .maybeSingle();
      final value = response?['last_read_at'] as String?;
      return value == null ? null : DateTime.tryParse(value);
    } catch (error) {
      debugPrint('Error fetching last seen: $error');
      return null;
    }
  }

  Future<int> countUnreadSince(String chatId, DateTime since) async {
    try {
      final me = await getUserId();
      if (me == null) {
        return 0;
      }

      return await supabase
          .from('messages')
          .count(CountOption.exact)
          .eq('chat_id', chatId)
          .neq('sender_id', me)
          .gt('created_at', since.toIso8601String());
    } catch (error) {
      debugPrint('Error counting unread messages: $error');
      return 0;
    }
  }

  Future<List<dynamic>> getContacts() async {
    final local = await _localDb.getContacts();
    if (local.isNotEmpty) {
      // Return local instantly, background sync happens elsewhere
      return local;
    }

    final me = await getUserId();
    if (me == null) {
      return [];
    }

    try {
      final contactRows = await supabase
          .from('contacts')
          .select('contact_user_id, name')
          .eq('user_id', me)
          .timeout(const Duration(seconds: 5));

      if (contactRows.isEmpty) {
        return [];
      }

      final contactIds = contactRows
          .map<String>((row) => row['contact_user_id'] as String)
          .toList();
      final userRows = await supabase
          .from('users')
          .select('id, nickname')
          .inFilter('id', contactIds)
          .timeout(const Duration(seconds: 5));
      final nicknames = {
        for (final row in userRows)
          row['id'] as String: row['nickname'] as String?,
      };

      final result = <Map<String, dynamic>>[];
      for (final row in contactRows) {
        final id = row['contact_user_id'] as String;
        final contact = {
          'contact_user_id': id,
          'user_id': id,
          'name': row['name'] ?? nicknames[id] ?? 'Unknown',
        };
        result.add(contact);
        await _localDb.saveContact(contact);
      }
      return result;
    } catch (error) {
      debugPrint('Error fetching contacts: $error');
      return [];
    }
  }

  Future<void> deleteContact(String userId) async {
    final me = await getUserId();
    if (me == null) {
      throw Exception('User not authenticated');
    }

    try {
      await supabase.from('contacts').delete().or(
            'and(user_id.eq.$me,contact_user_id.eq.$userId),and(user_id.eq.$userId,contact_user_id.eq.$me)',
          );
    } catch (error) {
      debugPrint('Error deleting contact: $error');
      rethrow;
    }
  }

  Future<void> getNicknames(Set<String> userIds) async {
    final missing =
        userIds.where((id) => !_nicknameCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final rows = await supabase
          .from('users')
          .select('id, nickname')
          .inFilter('id', missing.toList())
          .timeout(const Duration(seconds: 5));
      for (final row in rows) {
        final id = row['id'] as String;
        _nicknameCache[id] =
            (row['nickname'] as String?) ?? 'User ${id.substring(0, 4)}';
      }
    } catch (error) {
      debugPrint('Error batch-fetching nicknames: $error');
    }
  }

  Future<String?> getUserNicknameById(String userId) =>
      getNicknameForUser(userId);
  Future<String?> getUserNickname() => getNickname();
  Future<String> generateQRCode() async => (await getUserId()) ?? '';

  Future<void> addContact(String userId) async {
    final me = await getUserId();
    if (me == null || me == userId) {
      return;
    }

    String? nickname;
    try {
      final userRow = await supabase
          .from('users')
          .select('nickname')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      nickname = userRow?['nickname'] as String?;
    } catch (error) {
      debugPrint('addContact: lookup nickname failed: $error');
    }

    // Local-first: persist locally so getContacts() returns the contact even
    // if the Supabase upsert below fails or is delayed by the network.
    // contactsStore has keyPath 'contact_user_id' (IndexedDB schema), but
    // the UI reads 'user_id' — store both to satisfy schema and UI.
    await _localDb.saveContact({
      'contact_user_id': userId,
      'user_id': userId,
      'name': nickname,
    });

    try {
      await supabase.from('contacts').upsert({
        'user_id': me,
        'contact_user_id': userId,
        'name': nickname,
      }).timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('addContact: Supabase upsert failed (will retry via sync): $error');
    }
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final me = await getUserId();
    if (me == null || query.trim().isEmpty) {
      return [];
    }
    final normalizedQuery = query.trim();

    final existingContacts = await supabase
        .from('contacts')
        .select('contact_user_id')
        .eq('user_id', me)
        .timeout(const Duration(seconds: 5));
    final excludedIds = {
      me,
      ...existingContacts
          .map<String>((row) => row['contact_user_id'] as String),
    };

    final rows = <dynamic>[];
    final seenIds = <String>{};

    // Nickname search is the default discovery flow for nearby/manual adds.
    final nicknameRows = await supabase
        .from('users')
        .select('id, nickname')
        .ilike('nickname', '%${_escapeIlike(normalizedQuery)}%')
        .limit(20)
        .timeout(const Duration(seconds: 5));
    for (final row in nicknameRows) {
      final userId = row['id'] as String;
      if (seenIds.add(userId)) {
        rows.add(row);
      }
    }

    // Exact ID search gives users a deterministic way to connect devices.
    if (_looksLikeUuid(normalizedQuery)) {
      final idRow = await supabase
          .from('users')
          .select('id, nickname')
          .eq('id', normalizedQuery)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (idRow != null) {
        final userId = idRow['id'] as String;
        if (seenIds.add(userId)) {
          rows.add(idRow);
        }
      }
    }

    return rows
        .where((row) => !excludedIds.contains(row['id'] as String))
        .map(
          (row) => {
            'user_id': row['id'],
            'name': row['nickname'],
          },
        )
        .toList();
  }

  Future<void> markChatRead(String chatId) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    await supabase
        .from('chat_members')
        .update({'last_read_at': DateTime.now().toIso8601String()})
        .eq('chat_id', chatId)
        .eq('user_id', me)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> setTypingStatus({
    required String chatId,
    required bool isTyping,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    try {
      await supabase
          .from('chat_members')
          .update({'typing': isTyping})
          .eq('chat_id', chatId)
          .eq('user_id', me)
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Error setting typing status: $error');
    }
  }

  Future<DateTime?> getOtherLastReadAt(String chatId) async {
    final me = await getUserId();
    if (me == null) {
      return null;
    }

    final rows = await supabase
        .from('chat_members')
        .select('user_id, last_read_at')
        .eq('chat_id', chatId);
    for (final row in rows) {
      final userId = row['user_id'] as String;
      if (userId == me) {
        continue;
      }

      final value = row['last_read_at'] as String?;
      return value == null ? null : DateTime.tryParse(value);
    }
    return null;
  }

  Future<bool> debugCreateContactById({
    required String contactUserId,
    String? name,
  }) async {
    try {
      await addContact(contactUserId);
      if (name != null && name.trim().isNotEmpty) {
        final me = await getUserId();
        if (me != null) {
          await supabase
              .from('contacts')
              .update({'name': name.trim()})
              .eq('user_id', me)
              .eq('contact_user_id', contactUserId);
        }
      }
      return true;
    } catch (error) {
      debugPrint('debugCreateContactById error: $error');
      return false;
    }
  }

  Future<void> subscribeToUserCalls({
    required String userId,
    required Function(Map<String, dynamic>) onCallReceived,
    required Function(Map<String, dynamic>) onCallAccepted,
    required Function(Map<String, dynamic>) onCallEnded,
  }) async {
    await unsubscribeUserCalls();
    final channel = supabase.channel('user_calls:$userId');
    channel
        .onBroadcast(
          event: 'call_initiation',
          callback: (payload) => onCallReceived(_unwrapBroadcast(payload)),
        )
        .onBroadcast(
          event: 'call_accept',
          callback: (payload) {
            final unwrapped = _unwrapBroadcast(payload);
            onCallAccepted(unwrapped);
            // Пробрасываем событие активному WebRTCCallScreen, чтобы он
            // отправил offer только после того, как callee подписан.
            _callAcceptedController.add(unwrapped);
          },
        )
        .onBroadcast(
          event: 'call_end',
          callback: (payload) => onCallEnded(_unwrapBroadcast(payload)),
        )
        .subscribe();
    _userCallsChannel = channel;
  }

  Future<void> unsubscribeUserCalls() async {
    if (_userCallsChannel != null) {
      await supabase.removeChannel(_userCallsChannel!);
      _userCallsChannel = null;
    }
  }

  Future<void> subscribeCalls({
    required String chatId,
    required Function(Map<String, dynamic>) onOfferReceived,
    required Function(Map<String, dynamic>) onAnswerReceived,
    required Function(Map<String, dynamic>) onIceCandidateReceived,
  }) async {
    await unsubscribeCalls();
    final channel = supabase.channel('chat_calls:$chatId');
    channel
        .onBroadcast(
          event: 'offer',
          callback: (payload) => onOfferReceived(_unwrapBroadcast(payload)),
        )
        .onBroadcast(
          event: 'answer',
          callback: (payload) => onAnswerReceived(_unwrapBroadcast(payload)),
        )
        .onBroadcast(
          event: 'ice_candidate',
          callback: (payload) =>
              onIceCandidateReceived(_unwrapBroadcast(payload)),
        )
        .subscribe();
    _chatCallsChannel = channel;
  }

  /// Supabase Realtime оборачивает broadcast-сообщения в `{event, payload,
  /// type}`. Нужные нам поля лежат во вложенном `payload`. Эта обёртка
  /// возвращает именно их, чтобы downstream-код видел плоский payload
  /// независимо от того, как его прислал сервер.
  Map<String, dynamic> _unwrapBroadcast(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    if (inner is Map) {
      return Map<String, dynamic>.from(inner);
    }
    return payload;
  }

  Future<void> unsubscribeCalls() async {
    if (_chatCallsChannel != null) {
      await supabase.removeChannel(_chatCallsChannel!);
      _chatCallsChannel = null;
    }
  }

  /// Subscribes to P2P signaling events (Offer/Answer/Candidate) for a chat.
  void subscribeP2PSignaling(String chatId) {
    final channel = supabase.channel('chat_p2p_signaling:$chatId');

    channel.onBroadcast(event: 'p2p_signal', callback: (payload) {
      final data = _unwrapBroadcast(payload);
      final type = data['type'] as String;
      final p2p = P2PService.instance;

      if (type == 'offer') {
        p2p.handleOffer(chatId, data);
      } else if (type == 'answer') {
        p2p.handleAnswer(chatId, data);
      } else if (type == 'ice_candidate') {
        p2p.handleIceCandidate(chatId, data);
      }
    }).subscribe();
  }

  Future<void> _sendP2PSignal(String chatId, Map<String, dynamic> data) async {
    await supabase.channel('chat_p2p_signaling:$chatId').sendBroadcastMessage(
      event: 'p2p_signal',
      payload: data,
    );
  }

  Future<void> sendP2POffer({
    required String chatId,
    required Map<String, dynamic> offer,
  }) async {
    await _sendP2PSignal(chatId, {...offer, 'type': 'offer'});
  }

  Future<void> sendP2PAnswer({
    required String chatId,
    required Map<String, dynamic> answer,
  }) async {
    await _sendP2PSignal(chatId, {...answer, 'type': 'answer'});
  }

  Future<void> sendP2PIceCandidate({
    required String chatId,
    required Map<String, dynamic> candidate,
  }) async {
    await _sendP2PSignal(chatId, {...candidate, 'type': 'ice_candidate'});
  }

  Future<String?> _getOtherUserId(String chatId) async {
    final me = await getUserId();
    if (me == null) {
      return null;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final useSupabase = prefs.getBool('useSupabase') ?? true;
      if (useSupabase) {
        final members = await supabase
            .from('chat_members')
            .select('user_id')
            .eq('chat_id', chatId)
            .timeout(const Duration(seconds: 3));
        for (final row in members) {
          final candidate = row['user_id'] as String;
          if (candidate != me) {
            return candidate;
          }
        }
        return null;
      }
    } catch (_) {
      // ignore online error and fallback
    }

    // Offline fallback
    final chat = await _localDb.getChatById(chatId);
    if (chat != null) {
      final membersList = chat['members'] as List<dynamic>? ?? [];
      for (final candidate in membersList) {
        if (candidate.toString() != me) {
          return candidate.toString();
        }
      }
    }
    return null;
  }

  Future<void> sendCallInitiation({
    required String chatId,
    bool isVideoCall = false,
  }) async {
    final me = await getUserId();
    final nickname = await getNickname();
    final otherUserId = await _getOtherUserId(chatId);
    if (me == null || otherUserId == null || otherUserId.isEmpty) {
      return;
    }

    final channel = supabase.channel('user_calls:$otherUserId');
    await channel.sendBroadcastMessage(
      event: 'call_initiation',
      payload: {
        'chat_id': chatId,
        'from_user_id': me,
        'from_nickname': nickname,
        'call_type': isVideoCall ? 'video' : 'audio',
      },
    );
    await _recordCallHistoryEvent(
      chatId: chatId,
      initiatorUserId: me,
      recipientUserId: otherUserId,
      direction: 'outgoing',
      status: 'initiated',
      metadata: {
        'from_nickname': nickname,
        'call_type': isVideoCall ? 'video' : 'audio',
      },
    );
  }

  Future<void> sendCallAccept({required String chatId}) async {
    final me = await getUserId();
    final otherUserId = await _getOtherUserId(chatId);
    if (me == null || otherUserId == null || otherUserId.isEmpty) {
      return;
    }

    final channel = supabase.channel('user_calls:$otherUserId');
    await channel.sendBroadcastMessage(
      event: 'call_accept',
      payload: {'chat_id': chatId},
    );
    await _recordCallHistoryEvent(
      chatId: chatId,
      initiatorUserId: otherUserId,
      recipientUserId: me,
      direction: 'incoming',
      status: 'accepted',
      answeredAt: DateTime.now(),
    );
  }

  Future<void> recordIncomingCall({
    required String chatId,
    required String fromUserId,
    String? fromNickname,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    await _recordCallHistoryEvent(
      chatId: chatId,
      initiatorUserId: fromUserId,
      recipientUserId: me,
      direction: 'incoming',
      status: 'initiated',
      metadata: {'from_nickname': fromNickname},
    );
  }

  Future<void> markIncomingCallDeclined({
    required String chatId,
    required String fromUserId,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    await _recordCallHistoryEvent(
      chatId: chatId,
      initiatorUserId: fromUserId,
      recipientUserId: me,
      direction: 'incoming',
      status: 'declined',
      endedAt: DateTime.now(),
    );
  }

  Future<void> markCurrentUserCallEnded({
    required String chatId,
    String status = 'ended',
  }) async {
    final me = await getUserId();
    final otherUserId = await _getOtherUserId(chatId);
    if (me == null || otherUserId == null || otherUserId.isEmpty) {
      return;
    }

    final historyRows = await supabase
        .from('call_history')
        .select('initiator_user_id, recipient_user_id, direction')
        .eq('chat_id', chatId)
        .or(
          'and(initiator_user_id.eq.$me,recipient_user_id.eq.$otherUserId),and(initiator_user_id.eq.$otherUserId,recipient_user_id.eq.$me)',
        )
        .order('started_at', ascending: false)
        .limit(1);

    if (historyRows.isEmpty) {
      return;
    }

    final row = historyRows.first;
    await _recordCallHistoryEvent(
      chatId: chatId,
      initiatorUserId: row['initiator_user_id'] as String,
      recipientUserId: row['recipient_user_id'] as String,
      direction: row['direction'] as String? ?? 'outgoing',
      status: status,
      endedAt: DateTime.now(),
    );
  }

  Future<void> sendCallEnd({required String chatId}) async {
    final me = await getUserId();
    final otherUserId = await _getOtherUserId(chatId);
    if (me == null || otherUserId == null || otherUserId.isEmpty) {
      return;
    }

    final channel = supabase.channel('user_calls:$otherUserId');
    await channel.sendBroadcastMessage(
      event: 'call_end',
      payload: {'chat_id': chatId},
    );
    await _recordCallHistoryEvent(
      chatId: chatId,
      initiatorUserId: me,
      recipientUserId: otherUserId,
      direction: 'outgoing',
      status: 'ended',
      endedAt: DateTime.now(),
    );
  }

  Future<void> sendOffer({
    required String chatId,
    required Map<String, dynamic> offer,
  }) async {
    final me = await getUserId();
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(
      event: 'offer',
      payload: {'sdp': offer, 'from_user_id': me},
    );
  }

  Future<void> sendAnswer({
    required String chatId,
    required Map<String, dynamic> answer,
  }) async {
    final me = await getUserId();
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(
      event: 'answer',
      payload: {'sdp': answer, 'from_user_id': me},
    );
  }

  Future<void> sendIceCandidate({
    required String chatId,
    required Map<String, dynamic> candidate,
  }) async {
    final me = await getUserId();
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(
      event: 'ice_candidate',
      payload: {'candidate': candidate, 'from_user_id': me},
    );
  }


  Future<void> _recordCallHistoryEvent({
    required String chatId,
    required String initiatorUserId,
    required String recipientUserId,
    required String direction,
    required String status,
    DateTime? answeredAt,
    DateTime? endedAt,
    Map<String, dynamic>? metadata,
  }) async {
    final event = {
      'chat_id': chatId,
      'initiator_user_id': initiatorUserId,
      'recipient_user_id': recipientUserId,
      'direction': direction,
      'status': status,
      'started_at': DateTime.now().toIso8601String(),
      'answered_at': answeredAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'metadata': metadata ?? <String, dynamic>{},
    };

    // Save locally first
    await _localDb.saveCall(event);

    try {
      await supabase.rpc(
        'upsert_call_history_event',
        params: {
          'p_chat_id': chatId,
          'p_initiator_user_id': initiatorUserId,
          'p_recipient_user_id': recipientUserId,
          'p_direction': direction,
          'p_status': status,
          'p_answered_at': answeredAt?.toIso8601String(),
          'p_ended_at': endedAt?.toIso8601String(),
          'p_metadata': metadata ?? <String, dynamic>{},
        },
      ).timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Error recording call history: $error');
    }
  }

  /// Возвращает историю звонков текущего пользователя.
  Future<List<Map<String, dynamic>>> getRecentCallHistory(
      {int limit = 12}) async {
    final local = await _localDb.getCalls();
    if (local.isNotEmpty) {
      // Sort and process local calls
      local.sort((a, b) => (b['started_at'] as String).compareTo(a['started_at'] as String));
      final me = await getUserId();
      final result = <Map<String, dynamic>>[];
      for (final row in local.take(limit)) {
        final initiatorUserId = row['initiator_user_id'] as String;
        final recipientUserId = row['recipient_user_id'] as String;
        final isOutgoing = initiatorUserId == me;
        final peerId = isOutgoing ? recipientUserId : initiatorUserId;
        final peerName = await getNicknameForUser(peerId) ?? 'Unknown';

        result.add({
          ...row,
          'peer_id': peerId,
          'peer_name': peerName,
          'is_outgoing': isOutgoing,
        });
      }
      return result;
    }

    final me = await getUserId();
    if (me == null) {
      return [];
    }

    try {
      final rows = await supabase
          .from('call_history')
          .select('*')
          .or('initiator_user_id.eq.$me,recipient_user_id.eq.$me')
          .order('started_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 5));

      final result = <Map<String, dynamic>>[];
      for (final row in rows) {
        final initiatorUserId = row['initiator_user_id'] as String;
        final recipientUserId = row['recipient_user_id'] as String;
        final isOutgoing = initiatorUserId == me;
        final peerId = isOutgoing ? recipientUserId : initiatorUserId;
        final peerName = await getNicknameForUser(peerId) ?? 'Unknown';

        final entry = {
          ...Map<String, dynamic>.from(row),
          'peer_id': peerId,
          'peer_name': peerName,
          'is_outgoing': isOutgoing,
        };
        result.add(entry);
        await _localDb.saveCall(entry);
      }
      return result;
    } catch (error) {
      debugPrint('Error loading call history: $error');
      return [];
    }
  }

  Future<void> syncLocalToSupabase() async {
    final me = await getUserId();
    if (me == null) return;

    final chats = await getChats();
    for (final chat in chats) {
      final chatId = chat['id'] as String;
      final localMessages = await _localDb.getMessages(chatId);

      try {
        final cloudResponse = await supabase
            .from('messages')
            .select('id')
            .eq('chat_id', chatId)
            .limit(100);

        final cloudIds = (cloudResponse as List).map((m) => m['id']).toSet();

        for (final msg in localMessages) {
          if (!cloudIds.contains(msg['id'])) {
            await supabase.from('messages').insert({
              ...msg,
              'synced_at': DateTime.now().toIso8601String(),
            });
          }
        }
      } catch (e) {
        debugPrint('Sync failed for chat $chatId: $e');
      }
    }
  }
}
