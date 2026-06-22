import 'package:flutter/material.dart';

import '../../../../services/diagnostics/service_status.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class ServiceStatusTile extends StatelessWidget {
  const ServiceStatusTile({super.key, required this.status});

  final ServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TgSpacing.md,
        vertical: TgSpacing.xs,
      ),
      child: FlatContainer(
        intensity: FlatIntensity.light,
        padding: const EdgeInsets.symmetric(
          horizontal: TgSpacing.md,
          vertical: TgSpacing.sm,
        ),
        child: MergeSemantics(
          child: Row(
            children: [
              Semantics(
                label: _semanticLabelFor(status.state),
                child: _StatusDot(state: status.state),
              ),
              const SizedBox(width: TgSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.label, style: TgTypography.bodyEmphasis),
                    const SizedBox(height: 2),
                    Text(
                      status.detail,
                      style: TgTypography.caption1.copyWith(
                        color: c.gray,
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
        return c.green;
      case HealthState.warn:
        return c.warning;
      case HealthState.error:
        return c.error;
      case HealthState.unknown:
        return c.gray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);

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
