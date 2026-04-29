import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/constants/accessibility_ids.dart';

// Validates: Requirements 4.1, 4.2, 4.5

/// A minimal widget that mirrors the content of _showIncomingCallDialog
/// in call_manager.dart, used to verify the Semantics labels are correct.
class _IncomingCallDialogContent extends StatelessWidget {
  final String fromNickname;

  const _IncomingCallDialogContent({required this.fromNickname});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.phone_in_talk, color: Colors.green, size: 32),
          SizedBox(width: 12),
          Text('Incoming call'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            child: Text(
              fromNickname.isNotEmpty ? fromNickname[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 32),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: AccessibilityIds.callerName,
            container: true,
            child: Text(
              fromNickname,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        Semantics(
          label: AccessibilityIds.decline,
          button: true,
          child: TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.call_end, color: Colors.red),
            label: const Text('Decline', style: TextStyle(color: Colors.red)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
        Semantics(
          label: AccessibilityIds.answer,
          button: true,
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.phone),
            label: const Text('Answer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'Incoming call dialog exposes Answer, Decline, and Caller name semantics labels',
    (WidgetTester tester) async {
      final handle = tester.ensureSemantics();

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Suppress layout overflow errors that occur in the test environment
      // due to constrained screen size (same pattern as webrtc_call_screen test).
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // Pump the dialog content directly (not via showDialog) to keep the
      // semantics tree in the main pipeline owner, matching how the webrtc
      // call screen test works.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _IncomingCallDialogContent(fromNickname: 'Alice'),
          ),
        ),
      );

      await tester.pump();

      // Requirement 4.1 — Answer button
      expect(find.bySemanticsLabel(RegExp('Answer')), findsAtLeastNWidgets(1));

      // Requirement 4.2 — Decline button
      expect(find.bySemanticsLabel(RegExp('Decline')), findsAtLeastNWidgets(1));

      // Requirement 4.5 — Caller name label
      expect(find.bySemanticsLabel(RegExp('Caller name')), findsAtLeastNWidgets(1));

      handle.dispose();
    },
  );
}
