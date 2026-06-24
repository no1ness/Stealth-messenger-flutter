import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:stealth/ui/widgets/outgoing_delivery_status_icon.dart';

/// Smoke tests for the four lifecycle states + the failed-state tap path.
/// Full golden tests are out of scope for this task — these assertions
/// pin down icon identity and color, which is what the design system
/// promises (no off-brand colours, fixed Material icon set).
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('OutgoingDeliveryStatusIcon', () {
    testWidgets('pending renders animated clock (systemGray2)', (tester) async {
      await tester.pumpWidget(wrap(
        const OutgoingDeliveryStatusIcon(status: 'pending'),
      ));
      // Pulsing icon — needs at least one frame for AnimationController.
      await tester.pump(const Duration(milliseconds: 100));

      final iconFinder = find.byIcon(Icons.access_time);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, TgThemeColors.light.gray);
      expect(icon.size, 16);
    });

    testWidgets('sent renders single check (gray)', (tester) async {
      await tester.pumpWidget(wrap(
        const OutgoingDeliveryStatusIcon(status: 'sent'),
      ));
      final iconFinder = find.byIcon(Icons.done);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, TgThemeColors.light.gray);
    });

    testWidgets('delivered renders double check (primary)', (tester) async {
      await tester.pumpWidget(wrap(
        const OutgoingDeliveryStatusIcon(status: 'delivered'),
      ));
      final iconFinder = find.byIcon(Icons.done_all);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, TgThemeColors.light.primary);
    });

    testWidgets('failed renders error icon (error)', (tester) async {
      await tester.pumpWidget(wrap(
        const OutgoingDeliveryStatusIcon(status: 'failed'),
      ));
      final iconFinder = find.byIcon(Icons.error_outline);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, TgThemeColors.light.error);
    });

    testWidgets('failed + onRetryNow makes the icon tappable', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(wrap(
        OutgoingDeliveryStatusIcon(
          status: 'failed',
          onRetryNow: () => tapCount += 1,
        ),
      ));
      await tester.tap(find.byIcon(Icons.error_outline));
      expect(tapCount, 1);
    });

    testWidgets('failed without onRetryNow is NOT tappable', (tester) async {
      await tester.pumpWidget(wrap(
        const OutgoingDeliveryStatusIcon(status: 'failed'),
      ));
      // No GestureDetector wrapping when onRetryNow is null — the icon
      // sits bare. Tapping is allowed but has no callback to verify; we
      // just assert the widget rendered without throwing.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('unknown status falls back to sent', (tester) async {
      await tester.pumpWidget(wrap(
        const OutgoingDeliveryStatusIcon(status: 'totally-unknown'),
      ));
      // Falls through to the default (`sent`) branch.
      expect(find.byIcon(Icons.done), findsOneWidget);
    });
  });
}
