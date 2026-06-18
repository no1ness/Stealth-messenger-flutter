import 'package:flutter/material.dart';

import '../../../../logging/logger.dart';
import '../../../../themes/apple_liquid/constants/app_colors.dart';
import '../../../../themes/apple_liquid/constants/app_spacing.dart';
import '../../../../themes/apple_liquid/constants/app_typography.dart';

/// Row of three single-select chips ("All", "Warnings", "Errors") that
/// drives the diagnostics screen's log filter.
class LevelFilterChips extends StatelessWidget {
  const LevelFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// Selected minimum-level. Mapped:
  /// - `LogLevel.debug` -> "All"
  /// - `LogLevel.warn`  -> "Warnings"
  /// - `LogLevel.error` -> "Errors"
  final LogLevel selected;
  final ValueChanged<LogLevel> onSelected;

  static const _items = <(String, LogLevel)>[
    ('Все', LogLevel.debug),
    ('Предупреждения', LogLevel.warn),
    ('Ошибки', LogLevel.error),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (final (label, level) in _items) ...[
            _Chip(
              label: label,
              isSelected: selected == level,
              onTap: () => onSelected(level),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.systemBlue.withValues(alpha: 0.2)
              : AppColors.systemGray6.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(
            color: isSelected ? AppColors.systemBlue : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.subheadlineEmphasis.copyWith(
            color: isSelected ? AppColors.systemBlue : AppColors.systemGray,
          ),
        ),
      ),
    );
  }
}
