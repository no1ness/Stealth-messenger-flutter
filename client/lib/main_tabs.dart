import 'package:flutter/material.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/widgets/debug_status_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_bottom_nav_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';
import 'package:stealth/ui/screens/calls_screen.dart';
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

    _screens = [
      ChatsScreen(initialChatId: widget.initialChatId),
      ContactsScreen(),
      const CallsScreen(),
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
              label: 'Чаты',
              semanticLabel: AccessibilityIds.chatsTab,
            ),
            GlassBottomNavBarItem(
              icon: Icons.people_outline,
              selectedIcon: Icons.people,
              label: 'Контакты',
              semanticLabel: AccessibilityIds.contactsTab,
            ),
            GlassBottomNavBarItem(
              icon: Icons.call_outlined,
              selectedIcon: Icons.call,
              label: 'Звонки',
              semanticLabel: AccessibilityIds.callsTab,
            ),
            GlassBottomNavBarItem(
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: 'Профиль',
              semanticLabel: AccessibilityIds.profileTab,
            ),
            GlassBottomNavBarItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: 'Настройки',
              semanticLabel: AccessibilityIds.settingsTab,
            ),
          ],
        ),
      ),
    );
  }
}
