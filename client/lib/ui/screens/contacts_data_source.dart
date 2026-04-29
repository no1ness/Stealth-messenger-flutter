import 'package:stealth/supabase_service.dart';

/// Abstract interface for loading contacts data. Allows testing ContactsScreen
/// without initializing Supabase.
abstract class ContactsDataSource {
  Future<List<dynamic>> getContacts();
  Future<void> deleteContact(String userId);
  Future<String?> getSafetyNumber(String userId);
  Future<List<dynamic>> searchUsers(String query);
  Future<void> addContact(String userId);
  Future<String?> findOrCreatePrivateChatWith(String userId);
  Future<void> sendCallInitiation({
    required String chatId,
    required bool isVideoCall,
  });
}

/// Default implementation that delegates to SupabaseService.
class SupabaseContactsDataSource implements ContactsDataSource {
  SupabaseContactsDataSource(this._service);

  final SupabaseService _service;

  @override
  Future<List<dynamic>> getContacts() => _service.getContacts();

  @override
  Future<void> deleteContact(String userId) =>
      _service.deleteContact(userId);

  @override
  Future<String?> getSafetyNumber(String userId) =>
      _service.getSafetyNumber(userId);

  @override
  Future<List<dynamic>> searchUsers(String query) =>
      _service.searchUsers(query);

  @override
  Future<void> addContact(String userId) => _service.addContact(userId);

  @override
  Future<String?> findOrCreatePrivateChatWith(String userId) =>
      _service.findOrCreatePrivateChatWith(userId);

  @override
  Future<void> sendCallInitiation({
    required String chatId,
    required bool isVideoCall,
  }) =>
      _service.sendCallInitiation(chatId: chatId, isVideoCall: isVideoCall);
}
