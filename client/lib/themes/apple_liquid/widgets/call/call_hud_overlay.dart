import 'package:flutter/material.dart';

import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_elevation.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/effects/scanline_overlay.dart';
import 'package:stealth/themes/apple_liquid/widgets/status_chip.dart';

/// Shared HUD overlay for the WebRTC call screens.
///
/// Renders identically in `webrtc_call_screen_native_impl.dart` and
/// `webrtc_call_screen_web.dart` so the in-call experience is the
/// same across platforms. Features:
///
/// - **Monospace duration timer** — `AppTypography.titleMono` reads
///   like a value out of `date`, not "ui copy".
/// - **Signature "E2E ENCRYPTED" badge** — pulsing blue glow + a
///   subtle scan-line overlay. The single most identifying moment in
///   the app.
/// - **Safety-number groups** — fingerprint under the peer name.
/// - **Telemetry strip** — Transport / Audio / Latency columns.
/// - **Rotating dashed ring** — 116px avatar halo on [avatarWidget].
/// - **Connection-quality `StatusChip`** — with glowing dot.
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

  /// Formatted duration ("00:42", "01:13:08"). The widget doesn't
  /// format — callers control granularity.
  final String duration;

  /// Short label for the connection chip ("GOOD", "RECONNECTING").
  final String connectionLabel;
  final StatusKind connectionKind;

  /// Safety-number fingerprint like "A2:5F · 90:1B · 7C:E4 · 31:88".
  final String? safetyNumber;

  /// Telemetry columns — keys are uppercase labels, values are the
  /// metric readouts (e.g. "Transport" → "RELAY").
  final Map<String, String>? telemetry;

  /// Optional large avatar widget to wrap with the rotating halo.
  final Widget? avatarWidget;

  @override
  State<CallHudOverlay> createState() => _CallHudOverlayState();
}

class _CallHudOverlayState extends State<CallHudOverlay>
    with SingleTickerProviderStateMixin {
  /// Drives the E2E badge pulse (2.4 s cycle).
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  /// Drives the avatar-ring rotation (24 s cycle).
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Duration timer — mono, prominent.
            Semantics(
              label: AccessibilityIds.callDurationTimer,
              child: Text(
                widget.duration,
                style: AppTypography.titleMono.copyWith(
                  color: AppColors.textOnGlass,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // E2E ENCRYPTED badge — pulsing glow.
            Semantics(
              label: AccessibilityIds.callEncryptedBadge,
              child: ScanlineOverlay(
                intensity: 1.0,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, _) {
                    final scale = 1 + _pulseAnim.value * 0.04;
                    final blurExtra = _pulseAnim.value * 8;
                    final shadows = AppElevation.level4
                        .map((s) => s.copyWith(
                              blurRadius: s.blurRadius + blurExtra,
                            ))
                        .toList();
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.systemBlue.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusRound,
                          ),
                          border: Border.all(
                            color: AppColors.systemBlue,
                            width: 1,
                          ),
                          boxShadow: shadows,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: AppColors.systemBlue,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Text(
                              'E2E ENCRYPTED',
                              style: AppTypography.caption1Emphasis.copyWith(
                                color: AppColors.systemBlue,
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
            ),
            const SizedBox(height: AppSpacing.xs),
            // Connection-quality readout with glowing dot.
            Semantics(
              label: AccessibilityIds.callConnectionStatus,
              child: _buildConnectionChip(),
            ),
            // Safety-number fingerprint.
            if (widget.safetyNumber != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                widget.safetyNumber!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamilyMono,
                  fontFamilyFallback: AppFontStacks.monoFallbacks,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            // Rotating dashed ring around avatar.
            if (widget.avatarWidget != null) ...[
              const SizedBox(height: AppSpacing.xl),
              _buildAvatarWithRing(),
            ],
            // Telemetry strip.
            if (widget.telemetry != null && widget.telemetry!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildTelemetryStrip(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionChip() {
    final color = _colorFor(widget.connectionKind);
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 0,
                  offset: Offset.zero,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            widget.connectionLabel,
            style: AppTypography.caption1Emphasis.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarWithRing() {
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
                  color: AppColors.systemBlue.withValues(alpha: 0.3),
                ),
              ),
              widget.avatarWidget!,
            ],
          ),
        );
      },
    );
  }

  Widget _buildTelemetryStrip() {
    final entries = widget.telemetry!.entries.toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.key.toUpperCase(),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamilyMono,
                  fontFamilyFallback: AppFontStacks.monoFallbacks,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  height: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                e.value,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamilyMono,
                  fontFamilyFallback: AppFontStacks.monoFallbacks,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static Color _colorFor(StatusKind kind) {
    switch (kind) {
      case StatusKind.pending:
        return AppColors.textSecondary;
      case StatusKind.success:
        return AppColors.systemGreen;
      case StatusKind.warn:
        return AppColors.systemOrange;
      case StatusKind.danger:
        return AppColors.systemRed;
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
