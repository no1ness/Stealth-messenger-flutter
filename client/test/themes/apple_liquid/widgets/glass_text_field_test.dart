import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/effects/chromatic_aberration.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';

/// Coverage for [GlassTextField] focus pulse + web perf-budget gate.
///
/// - Dark mode + focus gain → mounts [ChromaticAberration] for the
///   250 ms pulse; short-circuits back to plain input at rest.
/// - Light mode + focus gain → no ChromaticAberration in the tree
///   (gated out via brightness check inside the effect itself).
/// - **Web perf-budget regression gate** (the heart of this plan):
///   `flutter test` always runs with `kIsWeb == false`, so we cannot
///   exercise the cheap-ghost branch at runtime. Instead we assert
///   the **code shape** that protects it survives future refactors.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.dark}) {
    return MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets(
    'focus pulse mounts ChromaticAberration on focus gain (dark)',
    (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(host(
        GlassTextField(focusNode: focusNode, hintText: 'pin'),
      ));
      // At rest: pulse value is 0, short-circuit returns plain input.
      expect(find.byType(ChromaticAberration), findsNothing);

      focusNode.requestFocus();
      // One frame for focus to propagate + animation to start.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byType(ChromaticAberration),
        findsOneWidget,
        reason: 'focus gain must trigger the chromatic pulse',
      );

      // Settle past the 250 ms emphasized curve so value <= 0.01.
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byType(ChromaticAberration),
        findsNothing,
        reason: 'pulse must short-circuit at rest to keep idle perf flat',
      );

      focusNode.dispose();
    },
  );

  testWidgets(
    'light brightness gates out the focus pulse',
    (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(host(
        GlassTextField(focusNode: focusNode, hintText: 'pin'),
        brightness: Brightness.light,
      ));
      focusNode.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // The wrapping `AnimatedBuilder` will still mount during the
      // pulse, but `ChromaticAberration.build` returns the child
      // unchanged in light brightness — so no ColorFiltered ghosts
      // appear inside the field.
      expect(
        find.descendant(
          of: find.byType(GlassTextField),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
        reason: 'light brightness must skip the colour-split ghosts',
      );

      await tester.pump(const Duration(milliseconds: 350));
      focusNode.dispose();
    },
  );

  test(
    'web perf-budget regression gate — kIsWeb branch wired in source',
    () {
      // flutter test forces kIsWeb=false at the FlutterTestPlatform
      // level, so the runtime branch chosen by the build method
      // cannot be exercised here. The next best thing is to pin the
      // code shape: if a future refactor drops the kIsWeb gate or
      // the cheap _GlassFieldGhost wiring, this test fails loudly.
      //
      // Yes, this is source-as-fixture. It is intentional and
      // scoped: the contract being protected (web cost = cost of
      // border outline × 2, not 3× BackdropFilter) is not
      // expressible through pump in the standard test platform.
      final src = File(
        'lib/themes/apple_liquid/widgets/glass_text_field.dart',
      ).readAsStringSync();

      expect(
        src.contains("import 'package:flutter/foundation.dart';"),
        isTrue,
        reason: 'kIsWeb import must be present for the gate to compile',
      );
      expect(
        src.contains('kIsWeb'),
        isTrue,
        reason: 'kIsWeb branch must be present in the build method',
      );
      expect(
        src.contains('_GlassFieldGhost(focused:'),
        isTrue,
        reason:
            'web branch must pass _GlassFieldGhost as ghostBuilder — '
            'cheap ghost is the entire point of this plan',
      );
    },
  );
}
