import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import 'storage_service.dart';

class SupabaseService {
  final SupabaseClient supabase = Supabase.instance.client;
  final StorageService _storage = StorageService();
  final Uuid _uuid = const Uuid();
  final Map<String, String?> _nicknameCache = {};
  RealtimeChannel? _realtimeChannel;
  
  DateTime? _chatsLoadedAt;
  DateTime? _contactsLoadedAt;
  List<dynamic>? _cachedContacts;

  Future<String?> getUserId() async {
    return await _storage.read('userId');
  }

  Future<String?> getNickname() async {
    return await _storage.read('nickname');
  }

  Future<void> loginAsTestUser({required String userId, required String nickname}) async {
    try {
      await _storage.write('userId', userId);
      await _storage.write('nickname', nickname);
      debugPrint('Вход выполнен как тестовый пользователь: $nickname ($userId)');
      await ensureDefaultPrivateChats();
    } catch (e) {
      debugPrint('Ошибка при инициализации тестовых данных: $e');
    }
  }

  Future<void> ensureDefaultPrivateChats() async {
    try {
      final me = await getUserId();
      if (me == null) return;
      // Only create chat with POCO, not with self (GEEKOM)
      final partners = ['11111111-1111-1111-1111-111111111111'];
      for (final partner in partners) {
        if (partner != me) { // Don't create chat with self
          await findOrCreatePrivateChatWith(partner);
        }
      }
    } catch (e) {
      debugPrint('Error in ensureDefaultPrivateChats: $e');
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _nicknameCache.clear();
    _chatsLoadedAt = null;
    _contactsLoadedAt = null;
  }

  Future<String?> findOrCreatePrivateChatWith(String otherUserId) async {
    final me = await getUserId();
    if (me == null) return null;

    try {
      final existingChats = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', me);

      for (final chatRow in existingChats) {
        final chatId = chatRow['chat_id'] as String;
        final otherUserInChat = await supabase
            .from('chat_members')
            .select('user_id')
            .eq('chat_id', chatId)
            .eq('user_id', otherUserId)
            .maybeSingle();
        
        if (otherUserInChat != null) {
          // Found the chat, return it immediately.
          return chatId;
        }
      }

      // If no chat was found after checking all, create a new one.
      final newChat = await supabase
          .from('chats')
          .insert({'created_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String()})
          .select('id')
          .single();

      final chatId = newChat['id'] as String;

      await supabase.from('chat_members').insert([
        {'chat_id': chatId, 'user_id': me},
        {'chat_id': chatId, 'user_id': otherUserId},
      ]);

      return chatId;
    } catch (e) {
      debugPrint('Error finding or creating chat: $e');
      return null;
    }
  }

  Future<List<dynamic>> getChats() async {
    final me = await getUserId();
    debugPrint('DEBUG: getChats() called for user: $me');
    if (me == null) {
      debugPrint('DEBUG: User ID is null, returning empty list');
      return [];
    }

    try {
      // First, get all chat_ids for the user
      final chatMembersResponse = await supabase
          .from('chat_members')
          .select('chat_id')
          .eq('user_id', me);
      debugPrint('DEBUG: Found ${chatMembersResponse.length} chat memberships for user $me');

      if (chatMembersResponse.isEmpty) {
        debugPrint('DEBUG: No chat memberships found, returning empty list');
        return [];
      }

      final List<String> chatIds = chatMembersResponse.map<String>((row) => row['chat_id'] as String).toList();
      debugPrint('DEBUG: Chat IDs: $chatIds');

      // Then, get chat details for these IDs
      final chatsResponse = await supabase
          .from('chats')
          .select('id, created_at, updated_at')
          .inFilter('id', chatIds);
      debugPrint('DEBUG: chats query returned ${chatsResponse.length} rows');

      final List<dynamic> chats = [];
      for (final chat in chatsResponse) {
        final String chatId = chat['id'] as String;
        debugPrint('DEBUG: Processing chat ID: $chatId');
        final participants = await supabase
            .from('chat_members')
            .select('user_id')
            .eq('chat_id', chatId);
        final List<String> members = participants.map<String>((p) => (p['user_id'] as String)).toList();
        debugPrint('DEBUG: Chat $chatId has members: $members');
        chats.add({
          'id': chatId,
          'created_at': chat['created_at'],
          'updated_at': chat['updated_at'],
          'members': members,
        });
      }
      debugPrint('DEBUG: Returning ${chats.length} chats');
      return chats;
    } catch (e) {
      debugPrint('Error fetching chats: $e');
      return [];
    }
  }

  Future<String?> getNicknameForUser(String userId) async {
    if (_nicknameCache.containsKey(userId)) {
      return _nicknameCache[userId];
    }
    String? nickname;
    switch (userId) {
      case '11111111-1111-1111-1111-111111111111':
        nickname = 'POCO';
        break;
      case '22222222-2222-2222-2222-222222222222':
        nickname = 'GEEKOM';
        break;
      default:
        nickname = 'User ${userId.substring(0, 4)}';
    }
    _nicknameCache[userId] = nickname;
    return nickname;
  }

  Future<List<dynamic>> getMessages(String chatId) async {
    try {
      final response = await supabase
          .from('messages')
          .select('*')
          .eq('chat_id', chatId)
          .order('created_at', ascending: true);
      return response;
    } catch (e) {
      debugPrint('Error fetching messages for chat $chatId: $e');
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
    if (me == null) return;
    try {
      await supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': me,
        'content': content,
        'message_type': type,
        'reply_to_id': replyToId,
      });
      await supabase
          .from('chats')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', chatId);
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchLastMessage(String chatId) async {
    try {
      final response = await supabase
          .from('messages')
          .select('*')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error fetching last message: $e');
      return null;
    }
  }

  Future<DateTime?> getLastSeen(String chatId) async {
    try {
      final me = await getUserId();
      if (me == null) return null;
      final response = await supabase
          .from('chat_members')
          .select('last_read_at')
          .eq('chat_id', chatId)
          .eq('user_id', me)
          .maybeSingle();
      if (response != null && response['last_read_at'] != null) {
        return DateTime.parse(response['last_read_at']);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching last seen: $e');
      return null;
    }
  }

  Future<int> countUnreadSince(String chatId, DateTime since) async {
    try {
      final me = await getUserId();
      if (me == null) return 0;
      final count = await supabase
          .from('messages')
          .count(CountOption.exact)
          .eq('chat_id', chatId)
          .neq('sender_id', me)
          .gt('created_at', since.toIso8601String());
      return count;
    } catch (e) {
      debugPrint('Error counting unread messages: $e');
      return 0;
    }
  }

  Future<List<dynamic>> getContacts() async {
    final me = await getUserId();
    if (me == null) return [];

    try {
      final response = await supabase
          .from('users')
          .select('id, nickname')
          .neq('id', me);

      return response.map((profile) => {
        'user_id': profile['id'],
        'name': profile['nickname'],
      }).toList();

    } catch (e) {
      debugPrint('Error fetching contacts: $e');
      return [];
    }
  }

  Future<void> deleteContact(String userId) async {
    try {
      debugPrint('DEBUG: deleteContact called for userId: $userId');
      final me = await getUserId();
      if (me == null) throw Exception('User not authenticated');

      // Delete from contacts table if it exists
      await supabase
          .from('contacts')
          .delete()
          .or('and(user_id.eq.$me,contact_user_id.eq.$userId),and(user_id.eq.$userId,contact_user_id.eq.$me)');

      debugPrint('DEBUG: Contact deleted from database');
    } catch (e) {
      debugPrint('Error deleting contact: $e');
      throw e;
    }
  }
  // ===========================================================================
  // WebRTC Signaling Methods
  // ===========================================================================

  Future<void> subscribeToUserCalls({
    required String userId,
    required Function(Map<String, dynamic>) onCallReceived,
    required Function(Map<String, dynamic>) onCallAccepted,
    required Function(Map<String, dynamic>) onCallEnded,
  }) async {
    final channel = supabase.channel('user_calls:$userId');
    channel.onBroadcast(
      event: 'call_initiation',
      callback: (payload) => onCallReceived(payload),
    ).onBroadcast(
      event: 'call_accept',
      callback: (payload) => onCallAccepted(payload),
    ).onBroadcast(
      event: 'call_end',
      callback: (payload) => onCallEnded(payload),
    ).subscribe();
    _realtimeChannel = channel;
  }

  Future<void> unsubscribeUserCalls() async {
    if (_realtimeChannel != null) {
      await supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  Future<void> subscribeCalls({
    required String chatId,
    required Function(Map<String, dynamic>) onOfferReceived,
    required Function(Map<String, dynamic>) onAnswerReceived,
    required Function(Map<String, dynamic>) onIceCandidateReceived,
  }) async {
    final channel = supabase.channel('chat_calls:$chatId');
    channel.onBroadcast(
      event: 'offer',
      callback: (payload) => onOfferReceived(payload),
    ).onBroadcast(
      event: 'answer',
      callback: (payload) => onAnswerReceived(payload),
    ).onBroadcast(
      event: 'ice_candidate',
      callback: (payload) => onIceCandidateReceived(payload),
    ).subscribe();
    _realtimeChannel = channel;
  }

  Future<void> unsubscribeCalls() async {
    if (_realtimeChannel != null) {
      await supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }
  
  Future<String?> _getOtherUserId(String chatId) async {
    final me = await getUserId();
    if (me == null) return null;
    final members = await supabase
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId);
    return members
        .map((row) => row['user_id'] as String)
        .firstWhere((id) => id != me, orElse: () => '');
  }

  Future<void> sendCallInitiation({required String chatId}) async {
    final me = await getUserId();
    final nickname = await getNickname();
    final otherUserId = await _getOtherUserId(chatId);
    if (me == null || otherUserId == null || otherUserId.isEmpty) {
      debugPrint('Cannot send call initiation: missing user data.');
      return;
    }

    debugPrint('Sending call initiation to $otherUserId for chat $chatId');
    final channel = supabase.channel('user_calls:$otherUserId');
    await channel.sendBroadcastMessage(
      event: 'call_initiation',
      payload: {'chat_id': chatId, 'from_user_id': me, 'from_nickname': nickname},
    );
  }

  Future<void> sendCallAccept({required String chatId}) async {
    final me = await getUserId();
    final otherUserId = await _getOtherUserId(chatId);
    if (me == null || otherUserId == null || otherUserId.isEmpty) return;

    final channel = supabase.channel('user_calls:$otherUserId');
    await channel.sendBroadcastMessage(
      event: 'call_accept',
      payload: {'chat_id': chatId},
    );
  }

  Future<void> sendCallEnd({required String chatId}) async {
    final me = await getUserId();
    final otherUserId = await _getOtherUserId(chatId);
    if (me == null || otherUserId == null || otherUserId.isEmpty) return;

    final channel = supabase.channel('user_calls:$otherUserId');
    await channel.sendBroadcastMessage(
      event: 'call_end',
      payload: {'chat_id': chatId},
    );
  }

  Future<void> sendOffer({required String chatId, required Map<String, dynamic> offer}) async {
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(
      event: 'offer',
      payload: {'sdp': offer},
    );
  }

  Future<void> sendAnswer({required String chatId, required Map<String, dynamic> answer}) async {
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(
      event: 'answer',
      payload: {'sdp': answer},
    );
  }

  Future<void> sendIceCandidate({required String chatId, required Map<String, dynamic> candidate}) async {
    final channel = supabase.channel('chat_calls:$chatId');
    await channel.sendBroadcastMessage(
      event: 'ice_candidate',
      payload: {'candidate': candidate},
    );
  }
}