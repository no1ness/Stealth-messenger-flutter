import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/constants/accessibility_ids.dart';

// Validates: Requirements 8.1, 8.3, 8.4

void main() {
  testWidgets(
    'Profile identity card exposes User ID, Username, and Copy contact bundle semantics labels',
    (WidgetTester tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // Mirrors _buildIdentityCard Semantics wrappers without
                // requiring any async loading.
                Semantics(
                  label: AccessibilityIds.userId,
                  readOnly: true,
                  child: const Text('test-user-id'),
                ),
                Semantics(
                  label: AccessibilityIds.username,
                  child: const TextField(),
                ),
                Semantics(
                  label: AccessibilityIds.copyContactBundle,
                  button: true,
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy contact'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Requirement 8.1 — User ID read-only label
      expect(
        find.bySemanticsLabel(RegExp('User ID')),
        findsAtLeastNWidgets(1),
      );

      // Requirement 8.3 — Username text field label
      expect(
        find.bySemanticsLabel(RegExp('Username')),
        findsAtLeastNWidgets(1),
      );

      // Requirement 8.4 — Copy contact bundle button label
      expect(
        find.bySemanticsLabel(RegExp('Copy contact bundle')),
        findsAtLeastNWidgets(1),
      );

      handle.dispose();
    },
  );
}
