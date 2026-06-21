import 'package:flutter/material.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/helpers/responsive_breakpoints.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_theme_data.dart';
import 'package:stealth/ui/screens/calls_screen.dart';
import 'package:stealth/ui/screens/chats_screen.dart';
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
      const CallsScreen(),
      const ProfileScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CallManager(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = ResponsiveBreakpoints.isDesktop(constraints.maxWidth);

          if (isDesktop) {
            return _buildDesktopLayout();
          }
          return _buildMobileLayout();
        },
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StealthAnimatedBackground(
        child: Column(
          children: [
            const DebugStatusBar(),
            Expanded(
              child: Row(
                children: [
                  _buildDesktopNavRail(),
                  Expanded(
                    child: _screens[_currentIndex],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopNavRail() {
    return Container(
      width: 68,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: AppColors.dividerSubtle,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildNavIconButton(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            index: 0,
          ),
          _buildNavIconButton(
            icon: Icons.call_outlined,
            selectedIcon: Icons.call,
            index: 1,
          ),
          const Spacer(),
          _buildNavIconButton(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            index: 2,
          ),
          _buildNavIconButton(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            index: 3,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildNavIconButton({
    required IconData icon,
    required IconData selectedIcon,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _currentIndex = index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: isSelected
                ? BoxDecoration(
                    color: AppColors.systemBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? AppColors.systemBlue : AppColors.textSecondary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
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
    );
  }
}
