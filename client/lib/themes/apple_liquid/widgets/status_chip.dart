import 'package:flutter/material.dart';

import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';

/// Semantic categories for [StatusChip].
enum StatusKind { pending, success, warn, danger }

/// Pill-shaped status indicator.
///
/// Used by the WebRTC diagnostics screen (connectivity / codec /
/// permissions checks) and by the in-call HUD (connection-quality
/// readout). Colour is driven by [kind]; label can be any short
/// string.
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
    final color = _colorFor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
        border: Border.all(
          color: color.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: AppTypography.caption1Emphasis.copyWith(color: color),
      ),
    );
  }

  static Color _colorFor(StatusKind kind) {
    switch (kind) {
      case StatusKind.pending:
        return AppColors.textSecondary;
      case StatusKind.success:
        return AppColors.statusSuccess;
      case StatusKind.warn:
        return AppColors.statusWarn;
      case StatusKind.danger:
        return AppColors.statusDanger;
    }
  }
}
