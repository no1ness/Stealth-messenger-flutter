import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/widgets/chats/chat_tile.dart';

void main() {
  testWidgets('renders chat tile with encrypted glyph', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTile(
            chat: const {
              'name': 'Alice',
              'lastMessage': 'Hello!',
              'unreadCount': 0,
              'isPrivate': true,
            },
            isSelected: false,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Hello!'), findsOneWidget);
    // The encrypted glyph '⌬' should be rendered before the message
    expect(find.textContaining('⌬'), findsOneWidget);
  });

  testWidgets('renders delivery tick marks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTile(
            chat: const {
              'name': 'Bob',
              'lastMessage': 'Hey',
              'unreadCount': 0,
              'isPrivate': true,
            },
            isSelected: false,
            onTap: () {},
            isSent: true,
            isDelivered: false,
            isRead: false,
          ),
        ),
      ),
    );

    // Single tick for sent
    expect(find.textContaining('✓'), findsOneWidget);
  });

  testWidgets('renders double tick for read messages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTile(
            chat: const {
              'name': 'Charlie',
              'lastMessage': 'See you',
              'unreadCount': 0,
              'isPrivate': true,
            },
            isSelected: false,
            onTap: () {},
            isSent: true,
            isDelivered: true,
            isRead: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('✓✓'), findsOneWidget);
  });
}
