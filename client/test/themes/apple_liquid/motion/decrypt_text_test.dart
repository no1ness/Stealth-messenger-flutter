import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/motion/decrypt_text.dart';

/// Coverage for [DecryptText].
///
/// - Empty string → renders `SizedBox.shrink()`.
/// - Reduce-motion (`MediaQuery.disableAnimations: true`) → resolves
///   to the final string immediately (no scramble frames).
/// - Animation lifecycle: pre-animation tick shows scramble; after
///   the controller settles past the resolution window the final
///   string is shown.
void main() {
  Widget host(Widget child, {bool disable = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disable),
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('empty string renders SizedBox.shrink', (tester) async {
    await tester.pumpWidget(host(const DecryptText('')));
    await tester.pump();
    expect(find.byType(SizedBox), findsAtLeast(1));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets(
    'disableAnimations → final string rendered immediately',
    (tester) async {
      await tester.pumpWidget(host(
        const DecryptText('STEALTH'),
        disable: true,
      ));
      // pump twice: postFrameCallback fires, controller jumps to 1.
      await tester.pump();
      await tester.pump();
      expect(find.text('STEALTH'), findsOneWidget);
    },
  );

  testWidgets(
    'animation resolves to the final string after duration completes',
    (tester) async {
      await tester.pumpWidget(host(
        const DecryptText(
          'STEALTH',
          duration: Duration(milliseconds: 200),
        ),
      ));
      // First frame: controller hasn't started forward() yet (deferred
      // to post-frame callback).
      await tester.pump();
      // Drive past the duration so the controller settles at 1.0.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 250));
      // After the animation completes, the final string is shown.
      expect(find.text('STEALTH'), findsOneWidget);
    },
  );

  testWidgets(
    'scramble alphabet — output stays inside [target + alphabet] character set',
    (tester) async {
      await tester.pumpWidget(host(
        const DecryptText(
          'STEALTH',
          duration: Duration(milliseconds: 300),
        ),
      ));
      await tester.pump();
      // Sample mid-animation: characters should be hex (0-9A-F) or
      // members of "STEALTH".
      await tester.pump(const Duration(milliseconds: 30));

      // Find ANY rendered Text descendant of DecryptText and confirm
      // its content matches the allowed alphabet.
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(DecryptText),
          matching: find.byType(Text),
        ),
      );
      expect(texts, isNotEmpty);
      final allowed = RegExp(r'^[STEALH0-9A-F ]+$');
      for (final t in texts) {
        final raw = t.data ?? '';
        expect(
          allowed.hasMatch(raw),
          isTrue,
          reason: 'unexpected character in scramble: "$raw"',
        );
      }
      // Let the animation settle to end with no pending timers.
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'staggered reveal — early chars resolve before later ones (regression gate)',
    (tester) async {
      // Regression gate for the resolution-math bug: the original
      // formula collapsed to `progress >= 1.0` for every index,
      // making the entire string scramble until end and then snap
      // to target. After fix, characters resolve in left-to-right
      // order during the timeline — by the time progress is past
      // (1 - window) (≈ 0.40 for n=7), the FIRST character must
      // already be locked to its target while the LAST character
      // can still be scrambling.
      await tester.pumpWidget(host(
        const DecryptText(
          'STEALTH',
          duration: Duration(milliseconds: 1000),
        ),
      ));
      await tester.pump();
      // Pump to ~80% of timeline. Last char's start = 6 * 0.1 = 0.6,
      // window = 0.4, so it's mid-resolution. First char (start = 0,
      // window = 0.4) should be fully resolved at progress >= 0.4.
      await tester.pump(const Duration(milliseconds: 800));

      String currentRender() {
        final widgets = tester
            .widgetList<Text>(find.descendant(
              of: find.byType(DecryptText),
              matching: find.byType(Text),
            ))
            .toList();
        return widgets.isEmpty ? '' : (widgets.first.data ?? '');
      }

      final rendered = currentRender();
      expect(
        rendered.length,
        7,
        reason: 'render must keep "STEALTH" length',
      );
      expect(
        rendered[0],
        'S',
        reason:
            'first character must be locked to target well before '
            'animation end (regression: pre-fix bug snapped all chars '
            'simultaneously at progress == 1.0)',
      );

      // Drain remaining timers so the test ends cleanly.
      await tester.pump(const Duration(milliseconds: 400));
    },
  );
}
