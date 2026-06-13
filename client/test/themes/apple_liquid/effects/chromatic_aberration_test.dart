import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/effects/chromatic_aberration.dart';

/// Coverage for [ChromaticAberration].
///
/// Contract:
/// - `intensity == 0` short-circuits to the child unchanged (no
///   ghost layers, no RepaintBoundary wrapper).
/// - Light mode auto-gates to the child unchanged (same dual-identity
///   contract as `ScanlineOverlay` / `GrainOverlay`).
/// - `force: true` bypasses the light-mode gate (tests + rare cases).
/// - Active state: child is rendered 3× (baseline + red ghost +
///   cyan ghost) — verified via descendant count.
void main() {
  Widget wrap(ThemeMode mode, Widget child) {
    final brightness =
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
    return MaterialApp(
      themeMode: mode,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: Theme(
        data: ThemeData(brightness: brightness),
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'intensity == 0 → child rendered without effect wrapper',
    (tester) async {
      const childKey = ValueKey('input');
      await tester.pumpWidget(wrap(
        ThemeMode.dark,
        const ChromaticAberration(
          intensity: 0,
          child: SizedBox(key: childKey, width: 100, height: 20),
        ),
      ));
      expect(find.byKey(childKey), findsOneWidget);
      // No coloured ghost layers should mount: ColorFiltered is the
      // signature of the active state.
      expect(
        find.descendant(
          of: find.byType(ChromaticAberration),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'dark mode + intensity > 0 → renders red and cyan ghost layers',
    (tester) async {
      await tester.pumpWidget(wrap(
        ThemeMode.dark,
        const ChromaticAberration(
          intensity: 1.0,
          child: SizedBox(width: 100, height: 20),
        ),
      ));
      // Two ColorFiltered ghosts: one red, one cyan.
      expect(
        find.descendant(
          of: find.byType(ChromaticAberration),
          matching: find.byType(ColorFiltered),
        ),
        findsNWidgets(2),
      );
      // RepaintBoundary discipline for signature effects.
      expect(
        find.descendant(
          of: find.byType(ChromaticAberration),
          matching: find.byType(RepaintBoundary),
        ),
        findsAtLeast(1),
      );
    },
  );

  testWidgets(
    'light mode → gate skips effect entirely',
    (tester) async {
      await tester.pumpWidget(wrap(
        ThemeMode.light,
        const ChromaticAberration(
          intensity: 1.0,
          child: SizedBox(width: 100, height: 20),
        ),
      ));
      expect(
        find.descendant(
          of: find.byType(ChromaticAberration),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
        reason: 'light mode must not paint colour ghosts',
      );
    },
  );

  testWidgets(
    'light mode + force: true → renders effect anyway',
    (tester) async {
      await tester.pumpWidget(wrap(
        ThemeMode.light,
        const ChromaticAberration(
          intensity: 1.0,
          force: true,
          child: SizedBox(width: 100, height: 20),
        ),
      ));
      expect(
        find.descendant(
          of: find.byType(ChromaticAberration),
          matching: find.byType(ColorFiltered),
        ),
        findsNWidgets(2),
        reason: 'force: true bypasses the light-mode gate',
      );
    },
  );
}
