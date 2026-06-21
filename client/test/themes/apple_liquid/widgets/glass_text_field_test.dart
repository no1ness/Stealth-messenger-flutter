import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/apple_liquid/effects/chromatic_aberration.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';

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
      'renders TextFormField',
      (tester) async {
        await tester.pumpWidget(wrap(
          ThemeMode.dark,
          const GlassTextField(hintText: 'Test'),
        ));
        expect(find.byType(TextFormField), findsOneWidget);
      },
    );

    testWidgets(
      'focus gain in dark mode mounts ChromaticAberration briefly',
      (tester) async {
        await tester.pumpWidget(wrap(
          ThemeMode.dark,
          const GlassTextField(hintText: 'Focus test'),
        ));
        final field = find.byType(TextFormField);
        expect(field, findsOneWidget);

        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ChromaticAberration),
          ),
          findsNothing,
        );

        await tester.showKeyboard(field);
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ChromaticAberration),
          ),
          findsOneWidget,
        );

        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ChromaticAberration),
          ),
          findsNothing,
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

        await tester.showKeyboard(field);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.descendant(
            of: find.byType(GlassTextField),
            matching: find.byType(ColorFiltered),
          ),
          findsNothing,
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
