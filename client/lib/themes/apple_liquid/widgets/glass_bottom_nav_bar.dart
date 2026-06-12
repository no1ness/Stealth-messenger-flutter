import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

class GlassBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassBottomNavBarItem> items;

  const GlassBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height:
              AppSpacing.tabBarHeight + MediaQuery.of(context).padding.bottom,
          decoration: BoxDecoration(
            color: AppColors.darkGray2.withValues(alpha: 0.8),
            border: const Border(
              top: BorderSide(
                color: AppColors.separator,
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                items.length,
                (index) => _GlassBottomNavBarItemWidget(
                  item: items[index],
                  isSelected: index == currentIndex,
                  onTap: () => onTap(index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassBottomNavBarItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const GlassBottomNavBarItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
  });
}

class _GlassBottomNavBarItemWidget extends StatefulWidget {
  final GlassBottomNavBarItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _GlassBottomNavBarItemWidget({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_GlassBottomNavBarItemWidget> createState() =>
      _GlassBottomNavBarItemWidgetState();
}

class _GlassBottomNavBarItemWidgetState
    extends State<_GlassBottomNavBarItemWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.item.label,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isSelected
                      ? (widget.item.selectedIcon ?? widget.item.icon)
                      : widget.item.icon,
                  color: widget.isSelected
                      ? AppColors.systemBlue
                      : AppColors.textSecondary,
                  size: AppSpacing.iconMd,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: widget.isSelected
                        ? AppColors.systemBlue
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
