import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: TgThemeData.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('TgChatBubble sent', () {
    testWidgets('renders sent bubble with message text', (tester) async {
      await tester.pumpWidget(wrap(
        const TgChatBubble(
          message: 'Hello',
          type: TgMessageType.sent,
        ),
      ));
      expect(find.text('Hello'), findsOneWidget);
    });
  });

  group('TgChatBubble received', () {
    testWidgets('renders received bubble with message text', (tester) async {
      await tester.pumpWidget(wrap(
        const TgChatBubble(
          message: 'Hi there',
          type: TgMessageType.received,
        ),
      ));
      expect(find.text('Hi there'), findsOneWidget);
    });
  });
}
