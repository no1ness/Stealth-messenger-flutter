import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/apple_liquid/effects/chromatic_aberration.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';

/// Coverage for [GlassTextField].
///
/// Contract:
/// - Focus gain in dark mode mounts [ChromaticAberration] briefly.
/// - Light mode gates out the chromatic-aberration pulse.
/// - Web perf-budget path uses `kIsWeb` guard and `_GlassFieldGhost`.
void main() {
  group('GlassTextField', () {
    Widget wrap(ThemeMode mode, Widget child) {
      final brightness =
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      return MaterialApp(
        themeMode: mode,
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        home: Theme(
          data: ThemeData(brightness: brightness),
          child: Scaffold(body: Center(child: child)),
        ),
      );
    }

    testWidgets(
      'focus gain in dark mode mounts ChromaticAberration briefly',
      (tester) async {
        await tester.pumpWidget(wrap(
          ThemeMode.dark,
          const GlassTextField(hintText: 'Test'),
        ));
        final field = find.byType(TextFormField);
        expect(field, findsOneWidget);

        // Before focus — no ChromaticAberration in tree.
        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ChromaticAberration),
          ),
          findsNothing,
          reason: 'idle field must not show ChromaticAberration',
        );

        // Gain focus — ChromaticAberration mounts.
        await tester.showKeyboard(field);
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ChromaticAberration),
          ),
          findsOneWidget,
          reason: 'focus gain must mount ChromaticAberration',
        );

        // Settle animation — ChromaticAberration disappears again.
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ChromaticAberration),
          ),
          findsNothing,
          reason: 'after settle ChromaticAberration must be gone',
        );
      },
    );

    testWidgets(
      'light brightness gates out the focus pulse',
      (tester) async {
        await tester.pumpWidget(wrap(
          ThemeMode.light,
          const GlassTextField(hintText: 'Light test'),
        ));
        final field = find.byType(TextFormField);
        expect(field, findsOneWidget);

        // Gain focus in light mode.
        await tester.showKeyboard(field);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // No ColorFiltered should appear inside GlassTextField (the
        // signature of ChromaticAberration ghost layers).
        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ColorFiltered),
          ),
          findsNothing,
          reason: 'light mode must not render colour ghost layers',
        );
      },
    );
  });

  group('web perf-budget regression gate (source-as-fixture)', () {
    test(
      'source contains kIsWeb import, kIsWeb branch, and _GlassFieldGhost wiring',
      () {
        final source = File(
          'lib/themes/apple_liquid/widgets/glass_text_field.dart',
        ).readAsStringSync();

        expect(
          source,
          contains("import 'package:flutter/foundation.dart'"),
          reason: 'missing kIsWeb import',
        );
        expect(
          source,
          contains('kIsWeb'),
          reason: 'missing kIsWeb guard in GlassTextField',
        );
        expect(
          source,
          contains('_GlassFieldGhost'),
          reason: 'missing _GlassFieldGhost widget reference',
        );
        expect(
          source,
          contains('ghostBuilder:'),
          reason: 'missing ghostBuilder wiring in ChromaticAberration call',
        );
      },
    );
  });
}
