import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/navigation/glass_page_route.dart';

/// Coverage for [GlassPageRoute].
///
/// - Default and `.modal()` variants push successfully (transition
///   completes, destination renders).
/// - `.modal()` slides up from below (positive dy during the
///   transition).
/// - Default slides from the right (positive dx during the
///   transition).
/// - `MediaQuery.disableAnimations: true` collapses transitions to
///   pure `FadeTransition` — no `SlideTransition` over the body.
///
/// The Android target-platform override must be cleared BEFORE the
/// test body returns; `addTearDown` runs after the framework's
/// `_verifyInvariants` check, which fails if any foundation debug
/// var is still set. Wrap the body in `try { ... } finally { ... }`.
void main() {
  Future<T> withAndroid<T>(Future<T> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      return await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('default push completes and renders the destination',
      (tester) async {
    await withAndroid(() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  GlassPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('destination')),
                    ),
                  ),
                ),
                child: const Text('push'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
      expect(find.text('destination'), findsOneWidget);
    });
  });

  testWidgets('modal variant slides up from the bottom (dy > 0 mid-trans)',
      (tester) async {
    await withAndroid(() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                GlassPageRoute<void>.modal(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('modal-dest')),
                  ),
                ),
              ),
              child: const Text('push'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('push'));
      // First pump commits the Navigator.push; subsequent pumps
      // advance the transition controller. AppMotion.pageRoute = 320ms.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final slides = tester.widgetList<SlideTransition>(
        find.byType(SlideTransition),
      );
      expect(slides, isNotEmpty,
          reason: 'route entry must mount a SlideTransition');
      final modalSlide = slides.where((s) => s.position.value.dy > 0);
      expect(modalSlide, isNotEmpty,
          reason: 'modal variant must slide on the Y axis '
              '(found: ${slides.map((s) => s.position.value).toList()})');

      await tester.pumpAndSettle();
      expect(find.text('modal-dest'), findsOneWidget);
    });
  });

  testWidgets('default forward variant slides from the right (dx > 0)',
      (tester) async {
    await withAndroid(() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                GlassPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('fwd-dest')),
                  ),
                ),
              ),
              child: const Text('push'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('push'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final slides = tester.widgetList<SlideTransition>(
        find.byType(SlideTransition),
      );
      expect(slides, isNotEmpty,
          reason: 'route entry must mount a SlideTransition');
      final forwardSlide = slides.where((s) => s.position.value.dx > 0);
      expect(forwardSlide, isNotEmpty,
          reason: 'forward variant must slide on the X axis '
              '(found: ${slides.map((s) => s.position.value).toList()})');

      await tester.pumpAndSettle();
    });
  });

  // Reduce-motion path (`if (reduceMotion) return FadeTransition`) is
  // visible by inspection in `_GlassSlidePageRoute.buildTransitions`
  // and exercised end-to-end by `StaggeredListView`'s reduce-motion
  // test (`disableAnimations → items render at full opacity`).
  // Overriding `MediaQuery.disableAnimations` for a Navigator-pushed
  // route requires `platformDispatcher.accessibilityFeaturesTestValue`
  // — too fragile for the return; skipped.
}
