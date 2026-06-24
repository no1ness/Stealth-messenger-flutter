import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

class TgBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<TgBottomNavBarItem> items;

  const TgBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Container(
      height: 56 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: c.backgroundSecondary,
        border: Border(top: BorderSide(color: c.dividers, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = index == currentIndex;
            return GestureDetector(
              onTap: () => onTap(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: TgSpacing.md, vertical: TgSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected ? (item.selectedIcon ?? item.icon) : item.icon,
                      color: isSelected ? c.primary : c.textSecondary,
                      size: TgSpacing.iconMd,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? c.primary : c.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class TgBottomNavBarItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final String? semanticLabel;

  const TgBottomNavBarItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.semanticLabel,
  });
}
