import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:stealth/crypto/ratchet_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'storage_service.dart';

class SupabaseService {
  static const String _attachmentsBucket = 'chat-media';
  final SupabaseClient supabase = Supabase.instance.client;
  final StorageService _storage = StorageService();
  final RatchetService _ratchet = RatchetService();
  final Map<String, String?> _nicknameCache = {};
  final X25519 _algorithm = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Map<String, SecretKey> _sharedSecretCache = {};

  /// Экранирует спецсимволы ILIKE для защиты от SQL-инъекций.
  static String _escapeIlike(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
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

  Future<String> encryptMessage(String content, String otherUserId, {int? ratchetIndex}) async {
    SecretKey key;
    if (ratchetIndex != null) {
      final myId = (await getUserId())!;
      final sharedSecret = await _getSharedSecret(otherUserId);
      final chains = await _ratchet.initializeChains(sharedSecret, myId, otherUserId);
      key = await _ratchet.getNthMessageKey(chains['mySendChain']!, ratchetIndex);
    } else {
      key = await _getSharedSecret(otherUserId);
    }
    return _encryptBytesWithSecret(Uint8List.fromList(utf8.encode(content)), key);
  }

  Future<String> decryptMessage(String payload, String otherUserId, {int? ratchetIndex}) async {
    try {
      if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(payload)) {
        return payload;
      }

      SecretKey key;
      if (ratchetIndex != null) {
        final myId = (await getUserId())!;
        final sharedSecret = await _getSharedSecret(otherUserId);
        final chains = await _ratchet.initializeChains(sharedSecret, myId, otherUserId);
        key = await _ratchet.getNthMessageKey(chains['theirSendChain']!, ratchetIndex);
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
      final rawKey = await _decryptBytesWithSecret(encryptedKey, envelopeSecret);
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
          .eq('user_id', me);
      for (final row in existingChats) {
        final chatId = row['chat_id'] as String;
        final otherUserInChat = await supabase
            .from('chat_members')
            .select('user_id')
            .eq('chat_id', chatId)
            .eq('user_id', otherUserId)
            .maybeSingle();
        if (otherUserInChat != null) {
          return chatId;
        }
      }

      final newChat = await supabase
          .from('chats')
          .insert({
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();
      final chatId = newChat['id'] as String;
      await supabase.from('chat_members').insert([
        {'chat_id': chatId, 'user_id': me},
        {'chat_id': chatId, 'user_id': otherUserId},
      ]);
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

    final uniqueMembers = {me, ...memberIds.where((id) => id.trim().isNotEmpty)}
        .toList();
    if (uniqueMembers.length < 3) {
      throw Exception('A group chat requires at least 3 members.');
    }

    try {
      final chat = await supabase
          .from('chats')
          .insert({
            'name': name.trim().isEmpty ? 'New group' : name.trim(),
            'is_private': false,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();
      final chatId = chat['id'] as String;

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
      final membership = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', me);
      if (membership.isEmpty) {
        return [];
      }

      final chatIds =
          membership.map<String>((row) => row['chat_id'] as String).toList();
      final chatsResponse = await supabase
          .from('chats')
          .select('id, name, is_private, created_at, updated_at, chat_members(user_id)')
          .inFilter('id', chatIds)
          .order('updated_at', ascending: false);

      return chatsResponse.map((chat) {
        final members = (chat['chat_members'] as List<dynamic>? ?? [])
            .map<String>((member) => member['user_id'] as String)
            .toList();
        return {
          'id': chat['id'],
          'name': chat['name'],
          'is_private': chat['is_private'],
          'created_at': chat['created_at'],
          'updated_at': chat['updated_at'],
          'members': members,
        };
      }).toList();
    } catch (error) {
      debugPrint('Error fetching chats: $error');
      return [];
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
        
    return digestStr.replaceAllMapped(RegExp(r'.{4}'), (match) => '${match.group(0)} ').trim();
  }

  Future<List<dynamic>> getMessages(
    String chatId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final otherUserId = await _getOtherUserId(chatId);
      final response = await supabase
          .from('messages')
          .select('*')
          .eq('chat_id', chatId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      if (otherUserId == null || otherUserId.isEmpty) {
        return List.from(response.reversed);
      }

      final reversed = List.from(response.reversed);
      for (final message in reversed) {
        final metadata = message['metadata'] as Map<String, dynamic>? ?? const {};
        final encryption = metadata['encryption'] as String?;
        final ratchetIndex = metadata['sender_ratchet_index'] as int?;
        if (encryption == 'group_e2e') {
          message['content'] = await _decryptGroupMessage(
            chatId,
            message['content'] as String,
          );
        } else {
          message['content'] = await decryptMessage(
            message['content'] as String,
            otherUserId,
            ratchetIndex: ratchetIndex,
          );
        }
      }
      return reversed;
    } catch (error) {
      debugPrint('Error fetching messages: $error');
      return [];
    }
  }

  Future<void> sendMessage({
    required String chatId,
    required String content,
    required String type,
    String? replyToId,
  }) async {
    final me = await getUserId();
    if (me == null) {
      return;
    }

    final otherUserId = await _getOtherUserId(chatId);

    try {
      final isGroupChat = otherUserId == null || otherUserId.isEmpty;
      
      int? ratchetIndex;
      if (!isGroupChat) {
        ratchetIndex = await supabase
            .from('messages')
            .count(CountOption.exact)
            .eq('chat_id', chatId)
            .eq('sender_id', me)
            .not('metadata->sender_ratchet_index', 'is', 'null');
      }

      final encryptedContent = isGroupChat
          ? await _encryptGroupMessage(chatId, content)
          : await encryptMessage(content, otherUserId, ratchetIndex: ratchetIndex);
          
      final metadata = <String, dynamic>{
        'encryption': isGroupChat ? 'group_e2e' : 'e2e',
      };
      if (ratchetIndex != null) {
        metadata['sender_ratchet_index'] = ratchetIndex;
      }

      await supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': me,
        'content': encryptedContent,
        'message_type': type,
        'reply_to_id': replyToId,
        'metadata': metadata,
      });
      await supabase
          .from('chats')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', chatId);
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
    
    final message = await supabase.from('messages').select('metadata').eq('id', messageId).single();
    final metadata = message['metadata'] as Map<String, dynamic>? ?? {};
    final ratchetIndex = metadata['sender_ratchet_index'] as int?;

    final encryptedContent = isGroupChat
        ? await _encryptGroupMessage(chatId, content)
        : await encryptMessage(content, otherUserId, ratchetIndex: ratchetIndex);

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
    await supabase
        .from('pinned_messages')
        .delete()
        .eq('message_id', messageId);
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
          .select('message_id, messages(id, content, message_type, metadata)')
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
      final otherUserId = await _getOtherUserId(chatId);
      final decodedContent = encryption == 'group_e2e'
          ? await _decryptGroupMessage(chatId, content)
          : (otherUserId == null || otherUserId.isEmpty
              ? content
              : await decryptMessage(content, otherUserId, ratchetIndex: ratchetIndex));

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
  }) async {
    final userId = await getUserId();
    if (userId == null) {
      return null;
    }

    final storagePath =
        '$userId/$chatId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      await supabase.storage
          .from(_attachmentsBucket)
          .uploadBinary(storagePath, bytes);
      return supabase.storage.from(_attachmentsBucket).getPublicUrl(storagePath);
    } catch (error) {
      debugPrint('Error uploading attachment bytes: $error');
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
      );
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

  /// Собирает метрики дашборда для адаптивного UI профиля/настроек.
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
      final chatMembers = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', me);
      final chatIds = chatMembers
          .map<String>((row) => row['chat_id'] as String)
          .toSet()
          .toList();

      var messageCount = 0;
      if (chatIds.isNotEmpty) {
        messageCount = await supabase
            .from('messages')
            .count(CountOption.exact)
            .inFilter('chat_id', chatIds);
      }

      final contactCount = await supabase
          .from('contacts')
          .count(CountOption.exact)
          .eq('user_id', me);
      final callCount = await supabase
          .from('call_history')
          .count(CountOption.exact)
          .or('initiator_user_id.eq.$me,recipient_user_id.eq.$me');
      final privateKey = await getPrivateKey();
      final bucketReady = await debugHasAttachmentBucket();

      return {
        'chatCount': chatIds.length,
        'contactCount': contactCount,
        'messageCount': messageCount,
        'callCount': callCount,
        'secureStorageReady': privateKey != null && privateKey.isNotEmpty,
        'hasPrivateKey': privateKey != null && privateKey.isNotEmpty,
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
        'hasPrivateKey': false,
        'bucketReady': false,
      };
    }
  }

  /// Возвращает 7 нормализованных столбцов активности за последнюю неделю.
  Future<List<double>> getWeeklyActivityBars() async {
    final me = await getUserId();
    if (me == null) {
      return List<double>.filled(7, 0.12);
    }

    try {
      final now = DateTime.now().toUtc();
      final start = now.subtract(const Duration(days: 6));

      final chatMembers = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', me);
      final chatIds = chatMembers
          .map<String>((row) => row['chat_id'] as String)
          .toSet()
          .toList();

      final messageRows = chatIds.isEmpty
          ? <dynamic>[]
          : await supabase
                .from('messages')
                .select('created_at')
                .inFilter('chat_id', chatIds)
                .gte('created_at', start.toIso8601String());

      final callRows = await supabase
          .from('call_history')
          .select('started_at')
          .or('initiator_user_id.eq.$me,recipient_user_id.eq.$me')
          .gte('started_at', start.toIso8601String());

      final buckets = List<int>.filled(7, 0);
      for (final row in messageRows) {
        final date = DateTime.tryParse(row['created_at'] as String? ?? '');
        if (date == null) {
          continue;
        }
        final diff = now.difference(date.toUtc()).inDays;
        if (diff >= 0 && diff < 7) {
          buckets[6 - diff] += 1;
        }
      }
      for (final row in callRows) {
        final date = DateTime.tryParse(row['started_at'] as String? ?? '');
        if (date == null) {
          continue;
        }
        final diff = now.difference(date.toUtc()).inDays;
        if (diff >= 0 && diff < 7) {
          buckets[6 - diff] += 2;
        }
      }

      final maxValue = buckets.fold<int>(1, (max, value) => value > max ? value : max);
      return buckets
          .map((value) => value == 0 ? 0.12 : (value / maxValue).clamp(0.12, 1.0))
          .toList();
    } catch (error) {
      debugPrint('Error loading weekly activity bars: $error');
      return List<double>.filled(7, 0.12);
    }
  }


  Future<Map<String, dynamic>?> fetchLastMessage(String chatId) async {
    try {
      final otherUserId = await _getOtherUserId(chatId);
      final response = await supabase
          .from('messages')
          .select('*')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (response != null && response['content'] is String) {
        final metadata = response['metadata'] as Map<String, dynamic>? ?? const {};
        final encryption = metadata['encryption'] as String?;
        final ratchetIndex = metadata['sender_ratchet_index'] as int?;
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
    final me = await getUserId();
    if (me == null) {
      return [];
    }

    try {
      final contactRows = await supabase
          .from('contacts')
          .select('contact_user_id, name')
          .eq('user_id', me);

      if (contactRows.isEmpty) {
        return [];
      }

      final contactIds = contactRows
          .map<String>((row) => row['contact_user_id'] as String)
          .toList();
      final userRows = await supabase
          .from('users')
          .select('id, nickname')
          .inFilter('id', contactIds);
      final nicknames = {
        for (final row in userRows) row['id'] as String: row['nickname'] as String?,
      };

      return contactRows.map((row) {
        final userId = row['contact_user_id'] as String;
        return {
          'user_id': userId,
          'name': (row['name'] as String?) ?? nicknames[userId] ?? 'Unknown',
        };
      }).toList();
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
      await supabase
          .from('contacts')
          .delete()
          .or(
            'and(user_id.eq.$me,contact_user_id.eq.$userId),and(user_id.eq.$userId,contact_user_id.eq.$me)',
          );
    } catch (error) {
      debugPrint('Error deleting contact: $error');
      rethrow;
    }
  }

  Future<void> getNicknames(Set<String> userIds) async {
    final missing = userIds.where((id) => !_nicknameCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final rows = await supabase
          .from('users')
          .select('id, nickname')
          .inFilter('id', missing.toList());
      for (final row in rows) {
        final id = row['id'] as String;
        _nicknameCache[id] = (row['nickname'] as String?) ?? 'User ${id.substring(0, 4)}';
      }
    } catch (error) {
      debugPrint('Error batch-fetching nicknames: $error');
    }
  }

  Future<String?> getUserNicknameById(String userId) => getNicknameForUser(userId);
  Future<String?> getUserNickname() => getNickname();
  Future<String> generateQRCode() async => (await getUserId()) ?? '';

  Future<void> addContact(String userId) async {
    final me = await getUserId();
    if (me == null || me == userId) {
      return;
    }

    final userRow = await supabase
        .from('users')
        .select('nickname')
        .eq('id', userId)
        .maybeSingle();
    final nickname = userRow?['nickname'] as String?;

    await supabase.from('contacts').upsert({
      'user_id': me,
      'contact_user_id': userId,
      'name': nickname,
    });
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final me = await getUserId();
    if (me == null || query.trim().isEmpty) {
      return [];
    }

    final existingContacts = await supabase
        .from('contacts')
        .select('contact_user_id')
        .eq('user_id', me);
    final excludedIds = {
      me,
      ...existingContacts
          .map<String>((row) => row['contact_user_id'] as String),
    };

    final rows = await supabase
        .from('users')
        .select('id, nickname')
        .ilike('nickname', '%${_escapeIlike(query.trim())}%')
        .limit(20);

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
        .eq('user_id', me);
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
          .eq('user_id', me);
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
          callback: (payload) => onCallReceived(payload),
        )
        .onBroadcast(
          event: 'call_accept',
          callback: (payload) => onCallAccepted(payload),
        )
        .onBroadcast(
          event: 'call_end',
          callback: (payload) => onCallEnded(payload),
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
        .onBroadcast(event: 'offer', callback: (payload) => onOfferReceived(payload))
        .onBroadcast(event: 'answer', callback: (payload) => onAnswerReceived(payload))
        .onBroadcast(
          event: 'ice_candidate',
          callback: (payload) => onIceCandidateReceived(payload),
        )
        .subscribe();
    _chatCallsChannel = channel;
  }

  Future<void> unsubscribeCalls() async {
    if (_chatCallsChannel != null) {
      await supabase.removeChannel(_chatCallsChannel!);
      _chatCallsChannel = null;
    }
  }

  Future<String?> _getOtherUserId(String chatId) async {
    final me = await getUserId();
    if (me == null) {
      return null;
    }

    final members = await supabase
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId);
    for (final row in members) {
      final candidate = row['user_id'] as String;
      if (candidate != me) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> sendCallInitiation({required String chatId}) async {
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
      },
    );
    await _recordCallHistoryEvent(
      chatId: chatId,
      initiatorUserId: me,
      recipientUserId: otherUserId,
      direction: 'outgoing',
      status: 'initiated',
      metadata: {'from_nickname': nickname},
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
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(event: 'offer', payload: {'sdp': offer});
  }

  Future<void> sendAnswer({
    required String chatId,
    required Map<String, dynamic> answer,
  }) async {
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(event: 'answer', payload: {'sdp': answer});
  }

  Future<void> sendIceCandidate({
    required String chatId,
    required Map<String, dynamic> candidate,
  }) async {
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(
      event: 'ice_candidate',
      payload: {'candidate': candidate},
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
      );
    } catch (error) {
      debugPrint('Error recording call history: $error');
    }
  }

  /// Возвращает историю звонков текущего пользователя.
  Future<List<Map<String, dynamic>>> getRecentCallHistory({int limit = 12}) async {
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
          .limit(limit);

      final result = <Map<String, dynamic>>[];
      for (final row in rows) {
        final initiatorUserId = row['initiator_user_id'] as String;
        final recipientUserId = row['recipient_user_id'] as String;
        final isOutgoing = initiatorUserId == me;
        final peerId = isOutgoing ? recipientUserId : initiatorUserId;
        final peerName = await getNicknameForUser(peerId) ?? 'Unknown';

        result.add({
          ...Map<String, dynamic>.from(row),
          'peer_id': peerId,
          'peer_name': peerName,
          'is_outgoing': isOutgoing,
        });
      }
      return result;
    } catch (error) {
      debugPrint('Error loading call history: $error');
      return [];
    }
  }
}
