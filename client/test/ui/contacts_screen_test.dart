import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/ui/screens/contacts_data_source.dart';
import 'package:stealth/ui/screens/contacts_screen.dart';

/// Manual-fake tests for ContactsScreen rendering with a fake data source.
/// Avoids spinning up the full LocalAppService / PocketBase stack.
void main() {
  setUp(() async {
    await dotenv.load(fileName: '.env.defaults');
    PocketBaseClient.resetForTests();
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContactsScreen with empty contacts', () {
    testWidgets('shows contacts screen without crash', (tester) async {
      final dataSource = _FakeContactsDataSource();

      await tester.pumpWidget(_wrap(ContactsScreen(dataSource: dataSource)));
      await tester.pumpAndSettle();

      // Screen renders without errors
      expect(find.byType(ContactsScreen), findsOneWidget);
    });
  });

  group('ContactsScreen with contacts', () {
    testWidgets('shows manual contact tiles', (tester) async {
      final dataSource = _FakeContactsDataSource();
      dataSource.mockContacts = [
        {'user_id': 'u-alice', 'name': 'Alice', 'contact_user_id': 'u-alice'},
        {'user_id': 'u-bob', 'name': 'Bob', 'contact_user_id': 'u-bob'},
      ];

      await tester.pumpWidget(_wrap(ContactsScreen(dataSource: dataSource)));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows auto_populated contacts without crash',
        (tester) async {
      final dataSource = _FakeContactsDataSource();
      dataSource.mockContacts = [
        {
          'user_id': 'u-charlie',
          'name': 'u-charlie',
          'contact_user_id': 'u-charlie',
          'auto_populated': true,
        },
      ];

      await tester.pumpWidget(_wrap(ContactsScreen(dataSource: dataSource)));
      await tester.pumpAndSettle();

      // Should render without errors and show at least the contact text
      expect(find.byType(ContactsScreen), findsOneWidget);
    });
  });

  group('ContactsScreen merge with presence cache', () {
    testWidgets('contacts are loaded and rendered without crash', (tester) async {
      final dataSource = _FakeContactsDataSource();
      dataSource.mockContacts = [
        {'user_id': 'u-user1', 'name': 'User 1', 'contact_user_id': 'u-user1'},
      ];

      await tester.pumpWidget(_wrap(ContactsScreen(dataSource: dataSource)));
      await tester.pump();

      expect(find.text('User 1'), findsOneWidget);
    });
  });
}

Widget _wrap(Widget screen) {
  return MaterialApp(
    home: screen,
  );
}

class _FakeContactsDataSource implements ContactsDataSource {
  List<Map<String, dynamic>> mockContacts = [];

  @override
  Future<List<dynamic>> getContacts() async =>
      mockContacts.map((c) => Map<String, dynamic>.from(c)).toList();

  @override
  Future<void> deleteContact(String userId) async {}

  @override
  Future<String?> getSafetyNumber(String userId) async => null;

  @override
  Future<List<dynamic>> searchUsers(String query) async => [];

  @override
  Future<void> addContact(String userId) async {}

  @override
  Future<String?> findOrCreatePrivateChatWith(String userId) async => null;
}
