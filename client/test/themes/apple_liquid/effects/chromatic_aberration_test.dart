import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/effects/chromatic_aberration.dart';

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
      expect(
        find.descendant(
          of: find.byType(ChromaticAberration),
          matching: find.byType(ColorFiltered),
        ),
        findsNWidgets(2),
      );
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
      );
    },
  );

  testWidgets(
    'ghostBuilder provides distinct widgets for ghost layers',
    (tester) async {
      const childKey = ValueKey('real-child');
      const ghostKey = ValueKey('ghost-layer');
      await tester.pumpWidget(wrap(
        ThemeMode.dark,
        ChromaticAberration(
          intensity: 1.0,
          child: const SizedBox(key: childKey, width: 100, height: 20),
          ghostBuilder: (_) => const SizedBox(key: ghostKey),
        ),
      ));
      expect(find.byKey(childKey), findsOneWidget);
      expect(find.byKey(ghostKey), findsNWidgets(2));
    },
  );

  testWidgets(
    'null ghostBuilder falls back to child for ghost layers',
    (tester) async {
      const childKey = ValueKey('backward-compat-child');
      await tester.pumpWidget(wrap(
        ThemeMode.dark,
        const ChromaticAberration(
          intensity: 1.0,
          child: SizedBox(key: childKey, width: 100, height: 20),
        ),
      ));
      expect(find.byKey(childKey), findsNWidgets(3));
    },
  );
}
