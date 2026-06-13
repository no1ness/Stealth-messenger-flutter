import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/effects/scanline_overlay.dart';

/// Coverage for [ScanlineOverlay] theme-aware auto-gating.
///
/// The contract is: in dark mode the overlay paints lines; in light
/// mode it passes the child through unchanged (no `CustomPaint`,
/// no `RepaintBoundary`). Pass `force: true` to bypass the gate
/// (tests + rare explicit-overlay scenarios).
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
    'dark mode: paints overlay (CustomPaint + RepaintBoundary present)',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ThemeMode.dark,
          const ScanlineOverlay(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );
      // The widget wraps in RepaintBoundary and paints via CustomPaint.
      expect(
        find.descendant(
          of: find.byType(ScanlineOverlay),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(ScanlineOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'light mode: gate skips overlay — no CustomPaint child',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ThemeMode.light,
          const ScanlineOverlay(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );
      // The child should render bare — ScanlineOverlay returns
      // child directly without wrapping in CustomPaint.
      expect(
        find.descendant(
          of: find.byType(ScanlineOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'light mode must NOT paint the overlay',
      );
      // SizedBox child still rendered.
      expect(
        find.descendant(
          of: find.byType(ScanlineOverlay),
          matching: find.byType(SizedBox),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'light mode + force:true: paints overlay anyway',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ThemeMode.light,
          const ScanlineOverlay(
            force: true,
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ScanlineOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
        reason: 'force: true bypasses the light-mode gate',
      );
    },
  );
}
