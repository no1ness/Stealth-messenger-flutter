import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

void main() {
  group('TgSearchField', () {
    testWidgets('renders with hint text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TgThemeData.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: TgSearchField(hintText: 'Search chats'),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Search chats'), findsOneWidget);
    });
  });
}
