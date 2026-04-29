import 'package:flutter/material.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/widgets/debug_status_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_bottom_nav_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';
import 'package:stealth/ui/screens/chats_screen.dart';
import 'package:stealth/ui/screens/contacts_screen.dart';
import 'package:stealth/ui/screens/profile_screen.dart';
import 'package:stealth/ui/screens/settings_screen.dart';
import 'package:stealth/ui/widgets/call_manager.dart';

class MainTabs extends StatefulWidget {
  const MainTabs({super.key, this.initialChatId});

  final String? initialChatId;

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    // Tab screens are created once so navigation state survives tab switches.
    _screens = [
      ChatsScreen(initialChatId: widget.initialChatId),
      ContactsScreen(),
      const ProfileScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CallManager(
      child: Scaffold(
        extendBody: true,
        body: StealthAnimatedBackground(
          child: Column(
            children: [
              const DebugStatusBar(),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: _screens,
                ),
              ),
            ],
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
              label: AccessibilityIds.chatsTab,
            ),
            GlassBottomNavBarItem(
              icon: Icons.people_outline,
              selectedIcon: Icons.people,
              label: AccessibilityIds.contactsTab,
            ),
            GlassBottomNavBarItem(
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: AccessibilityIds.profileTab,
            ),
            GlassBottomNavBarItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: AccessibilityIds.settingsTab,
            ),
          ],
        ),
      ),
    );
  }
}
