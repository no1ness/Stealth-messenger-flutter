import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

void main() {
  group('TgAppBar', () {
    testWidgets('renders title and back button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TgThemeData.light,
          home: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(kToolbarHeight),
              child: TgAppBar(title: 'Test Title', showBackButton: true),
            ),
          ),
        ),
      );
      expect(find.text('Test Title'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    });

    testWidgets('renders title without back button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TgThemeData.light,
          home: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(kToolbarHeight),
              child: TgAppBar(title: 'No Back'),
            ),
          ),
        ),
      );
      expect(find.text('No Back'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
    });
  });
}
