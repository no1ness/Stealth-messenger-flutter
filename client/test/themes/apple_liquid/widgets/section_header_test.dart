import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/widgets/section_header.dart';

/// Coverage for [SectionHeader].
///
/// Two things matter to verify here:
///
/// 1. Title text actually renders (basic smoke).
/// 2. The widget is exposed as a `Semantics(header: true)` node —
///    the Appium suite and screen readers both depend on it. If a
///    future refactor drops that flag, this test fails loud.
void main() {
  testWidgets('renders title text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionHeader(title: 'Privacy'),
        ),
      ),
    );
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('renders optional trailing widget when provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionHeader(
            title: 'Connection',
            trailing: TextButton(
              onPressed: () {},
              child: const Text('See all'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('exposes Semantics(header: true) — accessibility contract',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionHeader(title: 'Storage'),
        ),
      ),
    );
    final semantics = tester.getSemantics(find.text('Storage'));
    // The Semantics wrapper sets header: true and uses the title as
    // its label. Both are part of the public contract.
    expect(semantics.label, contains('Storage'));
    expect(
      semantics.flagsCollection.isHeader,
      isTrue,
      reason: 'SectionHeader must expose header: true to screen readers',
    );
  });

  testWidgets('renders count chip when count is provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionHeader(title: 'Закреплённые', count: 3),
        ),
      ),
    );
    expect(find.text('ЗАКРЕПЛЁННЫЕ'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
