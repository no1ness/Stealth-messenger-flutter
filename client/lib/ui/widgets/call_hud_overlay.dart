import 'package:flutter/material.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:stealth/ui/widgets/status_chip.dart';

class CallHudOverlay extends StatefulWidget {
  const CallHudOverlay({
    super.key,
    required this.duration,
    required this.connectionLabel,
    required this.connectionKind,
    this.safetyNumber,
    this.telemetry,
    this.avatarWidget,
  });

  final String duration;
  final String connectionLabel;
  final StatusKind connectionKind;
  final String? safetyNumber;
  final Map<String, String>? telemetry;
  final Widget? avatarWidget;

  @override
  State<CallHudOverlay> createState() => _CallHudOverlayState();
}

class _CallHudOverlayState extends State<CallHudOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(TgSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              label: AccessibilityIds.callDurationTimer,
              child: Text(
                widget.duration,
                style: TgTypography.titleMono.copyWith(
                  color: c.text,
                ),
              ),
            ),
            const SizedBox(height: TgSpacing.sm),
            Semantics(
              label: AccessibilityIds.callEncryptedBadge,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) {
                  final scale = 1 + _pulseAnim.value * 0.04;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TgSpacing.md,
                        vertical: TgSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(
                          TgSpacing.radiusRound,
                        ),
                        border: Border.all(
                          color: c.primary,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: c.primary,
                          ),
                          const SizedBox(width: TgSpacing.xxs),
                          Text(
                            'E2E ENCRYPTED',
                            style: TgTypography.caption1Emphasis.copyWith(
                              color: c.primary,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: TgSpacing.xs),
            Semantics(
              label: AccessibilityIds.callConnectionStatus,
              child: _buildConnectionChip(context),
            ),
            if (widget.safetyNumber != null) ...[
              const SizedBox(height: TgSpacing.lg),
              Text(
                widget.safetyNumber!,
                style: TgTypography.captionMono.copyWith(
                  color: c.textSecondary,
                  letterSpacing: 1.5,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (widget.avatarWidget != null) ...[
              const SizedBox(height: TgSpacing.xl),
              _buildAvatarWithRing(c),
            ],
            if (widget.telemetry != null && widget.telemetry!.isNotEmpty) ...[
              const SizedBox(height: TgSpacing.lg),
              _buildTelemetryStrip(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionChip(BuildContext context) {
    final c = TgThemeColors.of(context);
    final color = _colorFor(c, widget.connectionKind);
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: TgSpacing.xs),
          Text(
            widget.connectionLabel,
            style: TgTypography.caption1Emphasis.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarWithRing(TgThemeColors c) {
    return AnimatedBuilder(
      animation: _ringCtrl,
      builder: (context, _) {
        return SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(116, 116),
                painter: _DashedRingPainter(
                  progress: _ringCtrl.value,
                  color: c.primary.withValues(alpha: 0.3),
                ),
              ),
              widget.avatarWidget!,
            ],
          ),
        );
      },
    );
  }

  Widget _buildTelemetryStrip(BuildContext context) {
    final c = TgThemeColors.of(context);
    final entries = widget.telemetry!.entries.toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: TgSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.key.toUpperCase(),
                style: TgTypography.captionMono.copyWith(
                  color: c.textSecondary,
                  letterSpacing: 0.8,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: TgSpacing.xxs),
              Text(
                e.value,
                style: TgTypography.captionMono.copyWith(
                  color: c.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      }).toList(),
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

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashLength = 6.0;
    const gapLength = 4.0;
    final totalDash = dashLength + gapLength;
    final phase = -progress * totalDash * 6;

    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.save();

    final path = Path()..addOval(rect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = phase % totalDash;
      if (distance < 0) distance += totalDash;

      while (distance < metric.length) {
        final end = distance + dashLength;
        final extractedPath = metric.extractPath(
          distance.clamp(0, metric.length),
          end.clamp(0, metric.length),
        );
        canvas.drawPath(extractedPath, paint);
        distance += totalDash;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) =>
      old.progress != progress || old.color != color;
}
