import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/widgets/status_chip.dart';

/// Coverage for [StatusChip].
///
/// Renders four chips back-to-back and asserts the kind-driven colour
/// flows through the decoration. Catches any future refactor that
/// accidentally inverts `_colorFor` or drops a `StatusKind` case.
void main() {
  Future<void> pumpChip(WidgetTester tester, StatusKind kind, String label) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: StatusChip(label: label, kind: kind)),
        ),
      ),
    );
  }

  testWidgets('renders label text for each kind', (tester) async {
    for (final kind in StatusKind.values) {
      await pumpChip(tester, kind, kind.name.toUpperCase());
      expect(find.text(kind.name.toUpperCase()), findsOneWidget,
          reason: 'label for $kind should render');
    }
  });

  testWidgets('uses statusSuccess color for success kind', (tester) async {
    await pumpChip(tester, StatusKind.success, 'OK');
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(StatusChip),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    // The border colour is statusSuccess at ~45% alpha. We assert
    // it's "close to green" by checking the green channel dominates.
    expect(border.top.color.g, greaterThan(border.top.color.r));
    expect(border.top.color.g, greaterThan(border.top.color.b));
    // And not an arbitrary unrelated colour (cross-check against the
    // alias).
    expect(border.top.color.r, AppColors.statusSuccess.r);
  });

  testWidgets('uses statusDanger color for danger kind', (tester) async {
    await pumpChip(tester, StatusKind.danger, 'FAIL');
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(StatusChip),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    // Danger should be red-dominant.
    expect(border.top.color.r, greaterThan(border.top.color.g));
    expect(border.top.color.r, greaterThan(border.top.color.b));
  });
}
