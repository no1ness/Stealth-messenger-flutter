import 'package:stealth/local_app_service.dart';

/// Abstract interface for loading local contacts data.
abstract class ContactsDataSource {
  Future<List<dynamic>> getContacts();
  Future<void> deleteContact(String userId);
  Future<String?> getSafetyNumber(String userId);
  Future<List<dynamic>> searchUsers(String query);
  Future<void> addContact(String userId);
  Future<String?> findOrCreatePrivateChatWith(String userId);
}

/// Default implementation that delegates to LocalAppService.
class LocalContactsDataSource implements ContactsDataSource {
  LocalContactsDataSource(this._service);

  final LocalAppService _service;

  @override
  Future<List<dynamic>> getContacts() => _service.getContacts();

  @override
  Future<void> deleteContact(String userId) => _service.deleteContact(userId);

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
}
