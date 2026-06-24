import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

enum StatusKind { pending, success, warn, danger }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.kind,
  });

  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    final color = _colorFor(c, kind);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TgSpacing.sm,
        vertical: TgSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(TgSpacing.radiusRound),
        border: Border.all(
          color: color.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TgTypography.caption1Emphasis.copyWith(color: color),
      ),
    );
  }

  static Color _colorFor(TgThemeColors c, StatusKind kind) {
    switch (kind) {
      case StatusKind.pending:
        return c.textSecondary;
      case StatusKind.success:
        return c.success;
      case StatusKind.warn:
        return c.warning;
      case StatusKind.danger:
        return c.error;
    }
  }
}
