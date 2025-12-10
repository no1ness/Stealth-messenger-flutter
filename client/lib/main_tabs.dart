import 'package:flutter/material.dart';
import 'package:stealth/ui/screens/chats_screen.dart';
import 'package:stealth/ui/screens/contacts_screen.dart';
import 'package:stealth/ui/screens/profile_screen.dart';
import 'package:stealth/ui/screens/settings_screen.dart';
import 'package:stealth/themes/apple_liquid/widgets/circuit_board_background.dart';
import 'package:stealth/ui/widgets/call_manager.dart';

class MainTabs extends StatefulWidget {
  final String? initialChatId;
  const MainTabs({super.key, this.initialChatId});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _currentIndex = 0;

  String? _initialChatId;

  late final List<Widget> _screens = [
    ChatsScreen(initialChatId: _initialChatId),
    const ContactsScreen(),
    const ProfileScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initialChatId = widget.initialChatId;
  }

  @override
  Widget build(BuildContext context) {
    return CallManager(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CircuitBoardBackground(
          animated: true,
          child: _screens[_currentIndex],
        ),
        bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
      ),
    );
  }
}
