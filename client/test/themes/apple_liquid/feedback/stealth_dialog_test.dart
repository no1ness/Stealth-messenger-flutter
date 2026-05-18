import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/effects/scanline_overlay.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_dialog.dart';

/// Coverage for [showStealthDialog].
///
/// - Renders the title and body widget.
/// - Returns the result of a primary/secondary action when tapped.
/// - **2-tap destructive gate:** first tap arms (no dismissal, label
///   changes); second tap commits.
/// - `DialogImportance.high` mounts a [ScanlineOverlay] over the body.
void main() {
  Widget host(Future<void> Function(BuildContext) onTap) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          return Center(
            child: ElevatedButton(
              onPressed: () => onTap(ctx),
              child: const Text('open'),
            ),
          );
        }),
      ),
    );
  }

  testWidgets('renders title + body', (tester) async {
    await tester.pumpWidget(host((ctx) async {
      await showStealthDialog<void>(
        context: ctx,
        title: 'Are you sure?',
        body: const Text('This will sign you out.'),
        actions: const [
          StealthDialogAction<void>.primary(label: 'OK', result: null),
        ],
      );
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Are you sure?'), findsOneWidget);
    expect(find.text('This will sign you out.'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('primary action returns its result on tap', (tester) async {
    String? captured;
    await tester.pumpWidget(host((ctx) async {
      captured = await showStealthDialog<String>(
        context: ctx,
        title: 'pick',
        actions: const [
          StealthDialogAction<String>.primary(label: 'yes', result: 'YES'),
        ],
      );
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('yes'));
    await tester.pumpAndSettle();
    expect(captured, 'YES');
  });

  testWidgets(
    'destructive 2-tap gate: first tap arms (label flips, no dismiss)',
    (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(host((ctx) async {
        await showStealthDialog<bool>(
          context: ctx,
          title: 'delete?',
          actions: const [
            StealthDialogAction<bool>.destructive(
              label: 'Delete',
              result: true,
            ),
          ],
        );
        dismissed = true;
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // First tap → arms; label flips to "Confirm: Delete"; dialog stays.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm: Delete'), findsOneWidget);
      expect(dismissed, isFalse);

      // Second tap → commits.
      await tester.tap(find.text('Confirm: Delete'));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    },
  );

  testWidgets(
    'DialogImportance.high mounts a ScanlineOverlay (force or dark)',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        // Force dark so the ScanlineOverlay paints (it auto-gates in
        // light mode).
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(builder: (ctx) {
            return ElevatedButton(
              onPressed: () => showStealthDialog<void>(
                context: ctx,
                title: 'high-stakes',
                importance: DialogImportance.high,
                actions: const [
                  StealthDialogAction<void>.primary(label: 'OK', result: null),
                ],
              ),
              child: const Text('open'),
            );
          }),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ScanlineOverlay), findsOneWidget);
    },
  );
}
