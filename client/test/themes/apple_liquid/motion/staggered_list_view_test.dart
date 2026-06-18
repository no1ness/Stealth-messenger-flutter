import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/motion/staggered_list_view.dart';

/// Coverage for [StaggeredListView].
///
/// Contract under test:
/// - **Every item is wrapped in `RepaintBoundary`** (per 1.11 perf rule).
/// - **`disableAnimations: true`** skips the entrance animation —
///   items render at full opacity immediately.
void main() {
  Widget host(
    Widget child, {
    bool disable = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disable),
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'every item is wrapped in RepaintBoundary',
    (tester) async {
      await tester.pumpWidget(host(
        StaggeredListView.builder(
          itemCount: 5,
          itemBuilder: (_, i) => SizedBox(
            height: 40,
            child: Text('row-$i'),
          ),
        ),
      ));
      // Pump a frame so the ListView builds its visible items.
      await tester.pump();

      // For each row text, walking up the ancestor chain must find
      // a RepaintBoundary.
      for (var i = 0; i < 5; i++) {
        final repaintAncestors = find.ancestor(
          of: find.text('row-$i'),
          matching: find.byType(RepaintBoundary),
        );
        expect(
          repaintAncestors,
          findsAtLeast(1),
          reason:
              'item row-$i must have a RepaintBoundary ancestor (perf rule 1.11)',
        );
      }

      // Drain pending entry-animation timers (each item schedules a
      // Future.delayed(stagger * index)) so the test ends with no
      // pending timers.
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'disableAnimations → items render at full opacity, no FadeTransition wrap',
    (tester) async {
      await tester.pumpWidget(host(
        disable: true,
        StaggeredListView.builder(
          itemCount: 3,
          itemBuilder: (_, i) => SizedBox(
            height: 40,
            child: Text('row-$i'),
          ),
        ),
      ));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        // The item is inside RepaintBoundary → check that
        // RepaintBoundary's direct child is NOT a FadeTransition.
        final repaintBoundary = find.ancestor(
          of: find.text('row-$i'),
          matching: find.byType(RepaintBoundary),
        );
        final directChild = find.descendant(
          of: repaintBoundary.first,
          matching: find.byType(FadeTransition),
        );
        expect(
          directChild,
          findsNothing,
          reason:
              'reduce-motion users must not get the staggered entrance fade',
        );
      }
    },
  );
}
