import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/effects/scanline_overlay.dart';

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
      expect(
        find.descendant(
          of: find.byType(ScanlineOverlay),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
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
      );
    },
  );
}
