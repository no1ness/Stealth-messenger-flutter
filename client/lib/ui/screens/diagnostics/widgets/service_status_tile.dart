import 'package:flutter/material.dart';

import '../../../../services/diagnostics/service_status.dart';
import '../../../../themes/apple_liquid/components/glass_container.dart';
import '../../../../themes/apple_liquid/constants/app_colors.dart';
import '../../../../themes/apple_liquid/constants/app_spacing.dart';
import '../../../../themes/apple_liquid/constants/app_typography.dart';

class ServiceStatusTile extends StatelessWidget {
  const ServiceStatusTile({super.key, required this.status});

  final ServiceStatus status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: GlassContainer(
        intensity: GlassIntensity.light,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: MergeSemantics(
          child: Row(
            children: [
              Semantics(
                label: _semanticLabelFor(status.state),
                child: _StatusDot(state: status.state),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.label, style: AppTypography.bodyEmphasis),
                    const SizedBox(height: 2),
                    Text(
                      status.detail,
                      style: AppTypography.caption1.copyWith(
                        color: AppColors.systemGray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _semanticLabelFor(HealthState s) {
  switch (s) {
    case HealthState.ok:
      return 'OK';
    case HealthState.warn:
      return 'Warning';
    case HealthState.error:
      return 'Error';
    case HealthState.unknown:
      return 'Unknown';
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state});
  final HealthState state;

  Color get _color {
    switch (state) {
      case HealthState.ok:
        return AppColors.systemGreen;
      case HealthState.warn:
        return AppColors.systemOrange;
      case HealthState.error:
        return AppColors.systemRed;
      case HealthState.unknown:
        return AppColors.systemGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: _color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _color.withValues(alpha: 0.6),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}
