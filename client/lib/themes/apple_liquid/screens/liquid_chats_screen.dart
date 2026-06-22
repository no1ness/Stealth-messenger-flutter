import 'package:flutter/material.dart';
import 'package:stealth/ui/screens/chats_screen.dart';

// The themed shell forwards to the maintained adaptive screen.
class LiquidChatsScreen extends StatelessWidget {
  const LiquidChatsScreen({super.key, this.initialChatId});

  final String? initialChatId;

  @override
  Widget build(BuildContext context) {
    return ChatsScreen(initialChatId: initialChatId);
  }
}
