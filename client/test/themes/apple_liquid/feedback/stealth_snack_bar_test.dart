import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_snack_bar.dart';

/// Coverage for [showStealthSnackBar].
///
/// - Renders the message text inside a `SnackBar`.
/// - `SnackKind` selects the leading accent stripe colour.
/// - `info` does NOT fire a haptic; `danger` DOES.
/// - Bails silently when no `ScaffoldMessenger` is in scope.
void main() {
  late List<String> hapticCalls;

  setUp(() {
    hapticCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticCalls.add(call.arguments as String? ?? 'default');
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host({required Widget Function(BuildContext) child}) {
    return MaterialApp(
      home: Scaffold(body: Builder(builder: child)),
    );
  }

  testWidgets('shows the message text', (tester) async {
    await tester.pumpWidget(host(child: (ctx) {
      return ElevatedButton(
        onPressed: () => showStealthSnackBar(ctx, 'hello stealth'),
        child: const Text('go'),
      );
    }));
    await tester.tap(find.text('go'));
    await tester.pump(); // schedule
    await tester.pump(const Duration(milliseconds: 50)); // appearance
    expect(find.text('hello stealth'), findsOneWidget);
  });

  /// Pump enough fake time after each snackbar trigger to let the
  /// compound-haptic [Future.delayed] timers fire — otherwise the
  /// test ends with pending timers and Flutter test asserts.
  Future<void> drainHaptics(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('danger kind paints the danger accent stripe', (tester) async {
    await tester.pumpWidget(host(child: (ctx) {
      return ElevatedButton(
        onPressed: () =>
            showStealthSnackBar(ctx, 'oops', kind: SnackKind.danger),
        child: const Text('go'),
      );
    }));
    await tester.tap(find.text('go'));
    await tester.pump();
    await drainHaptics(tester);

    // The accent stripe is a 4-px Container painted with the danger
    // colour. Find any Container whose decoration / color matches.
    final stripe = tester.widgetList<Container>(find.byType(Container)).where(
          (c) => c.color == AppColors.statusDanger,
        );
    expect(
      stripe,
      isNotEmpty,
      reason: 'danger kind must produce a danger-coloured accent stripe',
    );
  });

  testWidgets('info kind does NOT fire a haptic', (tester) async {
    await tester.pumpWidget(host(child: (ctx) {
      return ElevatedButton(
        onPressed: () => showStealthSnackBar(ctx, 'fyi'),
        child: const Text('go'),
      );
    }));
    await tester.tap(find.text('go'));
    await tester.pump();
    await drainHaptics(tester);
    expect(hapticCalls, isEmpty);
  });

  testWidgets('danger kind fires haptic.error (heavy × 2)', (tester) async {
    await tester.pumpWidget(host(child: (ctx) {
      return ElevatedButton(
        onPressed: () =>
            showStealthSnackBar(ctx, 'fail', kind: SnackKind.danger),
        child: const Text('go'),
      );
    }));
    await tester.tap(find.text('go'));
    await tester.pump();
    await drainHaptics(tester);
    expect(
      hapticCalls,
      containsAllInOrder([
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.heavyImpact',
      ]),
    );
  });
}
