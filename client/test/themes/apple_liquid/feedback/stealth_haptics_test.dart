import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/feedback/stealth_haptics.dart';

/// Coverage for [StealthHaptics] platform-channel dispatch.
///
/// Channel mock records each `HapticFeedback.*` call so we can assert:
/// - convenience methods route to the right system call;
/// - compound patterns (`success`, `warn`, `error`) emit the correct
///   sequence of impacts in order;
/// - `MediaQuery.disableAnimations: true` silently suppresses output.
void main() {
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String? ?? 'default');
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('light → HapticFeedbackType.lightImpact', (tester) async {
    BuildContext? captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        captured = ctx;
        return const SizedBox.shrink();
      }),
    ));
    await StealthHaptics.light(captured!);
    expect(calls, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('medium → mediumImpact', (tester) async {
    BuildContext? captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        captured = ctx;
        return const SizedBox.shrink();
      }),
    ));
    await StealthHaptics.medium(captured!);
    expect(calls, ['HapticFeedbackType.mediumImpact']);
  });

  testWidgets('selection → selectionClick', (tester) async {
    BuildContext? captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        captured = ctx;
        return const SizedBox.shrink();
      }),
    ));
    await StealthHaptics.selection(captured!);
    expect(calls, ['HapticFeedbackType.selectionClick']);
  });

  // Compound patterns (`success`, `warn`, `error`) use `Future.delayed`
  // between impacts. testWidgets runs in a FakeAsync zone where
  // `Future.delayed` never resolves on its own — escape via
  // `tester.runAsync` so the awaits use wall-clock time.

  testWidgets('success → medium + light in order', (tester) async {
    BuildContext? captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        captured = ctx;
        return const SizedBox.shrink();
      }),
    ));
    await tester.runAsync(() => StealthHaptics.success(captured!));
    expect(calls, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('error → heavy × 2', (tester) async {
    BuildContext? captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        captured = ctx;
        return const SizedBox.shrink();
      }),
    ));
    await tester.runAsync(() => StealthHaptics.error(captured!));
    expect(calls, [
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets(
    'disableAnimations → silent no-op (no channel calls)',
    (tester) async {
      BuildContext? captured;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(builder: (ctx) {
            captured = ctx;
            return const SizedBox.shrink();
          }),
        ),
      ));
      await tester.runAsync(() async {
        await StealthHaptics.medium(captured!);
        await StealthHaptics.success(captured!);
        await StealthHaptics.error(captured!);
      });
      expect(calls, isEmpty,
          reason: 'reduce-motion users must not feel haptics');
    },
  );
}
