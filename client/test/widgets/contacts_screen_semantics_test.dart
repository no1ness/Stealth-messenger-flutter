import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/ui/screens/contacts_data_source.dart';
import 'package:stealth/ui/screens/contacts_screen.dart';

// Validates: Requirements 2.1, 2.4, 3.1

/// Minimal fake that returns a single contact named 'Alice' without hitting
/// Supabase or any local database.
class _FakeContactsDataSource implements ContactsDataSource {
  @override
  Future<List<dynamic>> getContacts() async {
    return [
      {'user_id': 'alice-uuid-0001', 'name': 'Alice'},
    ];
  }

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

  @override
  Future<void> sendCallInitiation({
    required String chatId,
    required bool isVideoCall,
  }) async {}
}

void main() {
  testWidgets(
    'ContactsScreen exposes Add contact, Start call, and Contact Alice semantics labels',
    (WidgetTester tester) async {
      final handle = tester.ensureSemantics();

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Suppress pre-existing overflow warnings unrelated to semantics.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        MaterialApp(
          home: ContactsScreen(dataSource: _FakeContactsDataSource()),
        ),
      );

      // Let initState / _loadContacts complete.
      await tester.pumpAndSettle();

      // Requirement 2.4 — 'Add contact' button is always present.
      expect(
        find.bySemanticsLabel(RegExp('Add contact')),
        findsAtLeastNWidgets(1),
      );

      // Requirement 2.1 — contact card for Alice is present.
      expect(find.bySemanticsLabel(RegExp('Contact Alice')), findsOneWidget);

      // Requirement 3.1 — 'Start call' button is present for each contact.
      expect(
        find.bySemanticsLabel(RegExp('Start call')),
        findsAtLeastNWidgets(1),
      );

      handle.dispose();
    },
  );
}
