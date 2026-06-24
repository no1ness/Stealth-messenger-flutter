import 'package:flutter/material.dart';

import '../../../../logging/logger.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

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
        horizontal: TgSpacing.md,
        vertical: TgSpacing.xs,
      ),
      child: Row(
        children: [
          for (final (label, level) in _items) ...[
            _Chip(
              label: label,
              isSelected: selected == level,
              onTap: () => onSelected(level),
            ),
            const SizedBox(width: TgSpacing.xs),
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
    final c = TgThemeColors.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: TgSpacing.md,
          vertical: TgSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? c.primary.withValues(alpha: 0.2)
              : c.gray.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(TgSpacing.radiusXl),
          border: Border.all(
            color: isSelected ? c.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TgTypography.subheadlineEmphasis.copyWith(
            color: isSelected ? c.primary : c.gray,
          ),
        ),
      ),
    );
  }
}
