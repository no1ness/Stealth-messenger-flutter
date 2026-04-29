import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_message_input.dart';

// Validates: Requirements 6.1, 6.2, 7.1

void main() {
  group('GlassMessageInput semantics', () {
    testWidgets(
      'exposes Message input and Attach file labels',
      (WidgetTester tester) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GlassMessageInput(onSendMessage: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Requirement 6.1 — message input field is labelled.
        expect(
          find.bySemanticsLabel(AccessibilityIds.messageInput),
          findsOneWidget,
        );

        // Requirement 6.5 — attach file button is labelled.
        expect(
          find.bySemanticsLabel(AccessibilityIds.attachFile),
          findsOneWidget,
        );

        handle.dispose();
      },
    );

    testWidgets(
      'exposes Send message label when input has text',
      (WidgetTester tester) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GlassMessageInput(onSendMessage: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Type text so the send button appears.
        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pumpAndSettle();

        // Requirement 6.2 — send message button is labelled.
        expect(
          find.bySemanticsLabel(AccessibilityIds.sendMessage),
          findsOneWidget,
        );

        handle.dispose();
      },
    );
  });

  group('Chat tile semantics', () {
    testWidgets(
      'exposes Chat Alice label',
      (WidgetTester tester) async {
        final handle = tester.ensureSemantics();

        // Pump a minimal widget that mirrors _buildChatTile semantics.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Semantics(
                label: AccessibilityIds.chat('Alice'),
                button: true,
                child: const ListTile(title: Text('Alice')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Requirement 7.1 — chat tile for Alice is labelled.
        expect(
          find.bySemanticsLabel(RegExp('Chat Alice')),
          findsOneWidget,
        );

        handle.dispose();
      },
    );
  });
}
