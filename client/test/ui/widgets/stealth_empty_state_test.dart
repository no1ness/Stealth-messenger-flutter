import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/ui/widgets/empty_state.dart';

/// Coverage for [StealthEmptyState].
///
/// - Renders the icon, title, optional message, and action.
/// - Action widget receives the user's tap.
/// - **Key-fingerprint backdrop** renders text in dark mode and
///   collapses to `SizedBox.shrink()` in light mode (per
///   design-system.md "Signature elements / Key-fingerprint backdrop").
void main() {
  Widget host(ThemeMode mode, Widget body) {
    final brightness =
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
    return MaterialApp(
      themeMode: mode,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: Theme(
        data: ThemeData(brightness: brightness),
        child: Scaffold(body: body),
      ),
    );
  }

  testWidgets('renders icon, title, message', (tester) async {
    await tester.pumpWidget(host(
      ThemeMode.dark,
      const StealthEmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No conversations',
        message: 'Send a contact bundle to start.',
      ),
    ));
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.text('No conversations'), findsOneWidget);
    expect(find.text('Send a contact bundle to start.'), findsOneWidget);
  });

  testWidgets('action widget responds to tap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(host(
      ThemeMode.dark,
      StealthEmptyState(
        icon: Icons.person_add_alt_1_outlined,
        title: 'Empty',
        action: ElevatedButton(
          onPressed: () => tapped++,
          child: const Text('Invite'),
        ),
      ),
    ));
    await tester.tap(find.text('Invite'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets(
    'key-fingerprint backdrop: dark mode renders a hex-pair pattern',
    (tester) async {
      await tester.pumpWidget(host(
        ThemeMode.dark,
        const StealthEmptyState.chats(),
      ));
      // Pattern is 14 rows × 8 hex pairs, joined by ':' and '\n'.
      // Each row matches /^[0-9A-F]{2}(:[0-9A-F]{2}){7}$/. Look for any
      // text widget whose content matches this shape.
      final matches = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) {
        final lines = s.split('\n');
        if (lines.length != 14) return false;
        final re = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){7}$');
        return lines.every(re.hasMatch);
      });
      expect(
        matches,
        isNotEmpty,
        reason:
            'dark-mode empty state must paint a 14×8 hex-pair fingerprint',
      );
    },
  );

  testWidgets(
    'key-fingerprint backdrop: light mode collapses to SizedBox.shrink()',
    (tester) async {
      await tester.pumpWidget(host(
        ThemeMode.light,
        const StealthEmptyState.contacts(),
      ));
      // In light mode the backdrop must not paint the hex grid.
      final matches = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) {
        final lines = s.split('\n');
        if (lines.length != 14) return false;
        final re = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){7}$');
        return lines.every(re.hasMatch);
      });
      expect(
        matches,
        isEmpty,
        reason: 'light-mode empty state must skip the fingerprint backdrop',
      );
    },
  );
}
