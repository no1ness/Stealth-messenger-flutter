import 'package:flutter/material.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/circuit_board_background.dart';
import '../constants/app_colors.dart';
import 'liquid_chats_screen.dart';
import 'liquid_contacts_screen.dart';
import 'liquid_profile_screen.dart';

class LiquidMainScreen extends StatefulWidget {
  const LiquidMainScreen({super.key});

  @override
  State<LiquidMainScreen> createState() => _LiquidMainScreenState();
}

class _LiquidMainScreenState extends State<LiquidMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    LiquidChatsScreen(),
    LiquidContactsScreen(),
    LiquidProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: CircuitBoardBackground(
        animated: true,
        child: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: GlassBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          GlassBottomNavBarItem(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            label: 'Chats',
          ),
          GlassBottomNavBarItem(
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            label: 'Contacts',
          ),
          GlassBottomNavBarItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
