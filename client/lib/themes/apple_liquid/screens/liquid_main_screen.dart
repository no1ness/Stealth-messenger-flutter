import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';

class LiquidMainScreen extends StatelessWidget {
  const LiquidMainScreen({super.key, this.initialChatId});

  final String? initialChatId;

  @override
  Widget build(BuildContext context) {
    return MainTabs(initialChatId: initialChatId);
  }
}
