import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_effects.dart';

/// Signature grain / noise overlay.
///
/// Paints a static procedural noise texture over [child] at the
/// opacity defined in [AppEffects.grainOpacity] (overridable per
/// call site). The texture sits behind a `RepaintBoundary` and uses
/// a deterministic seed so the grain pattern is stable across
/// rebuilds — important for snapshot tests.
///
/// **Theme-aware gating.** In [Brightness.light] the overlay
/// renders [child] unchanged. Pass `force: true` to bypass the gate
/// (tests only).
class GrainOverlay extends StatelessWidget {
  const GrainOverlay({
    super.key,
    required this.child,
    this.opacity = AppEffects.grainOpacity,
    this.force = false,
  });

  final Widget child;
  final double opacity;
  final bool force;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.light && !force) {
      debugPrint(
        '[fx:grain] gated-out brightness=light opacity=$opacity',
      );
      return child;
    }
    debugPrint(
      '[fx:grain] mount brightness=$brightness opacity=$opacity',
    );
    return RepaintBoundary(
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GrainPainter(opacity: opacity),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.opacity});

  final double opacity;

  // Deterministic seed so the grain pattern is stable across
  // rebuilds and snapshot tests.
  static const int _seed = 0x57414C4B; // "WALK"

  @override
  void paint(Canvas canvas, Size size) {
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    if (clampedOpacity <= 0) {
      return;
    }
    final cell = AppEffects.grainCellPx;
    final rng = math.Random(_seed);
    final paint = Paint();

    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        // Use a triangular distribution so the noise feels organic,
        // not pure white-noise harsh.
        final n = (rng.nextDouble() + rng.nextDouble()) / 2;
        final a = (n * clampedOpacity).clamp(0.0, 1.0);
        paint.color = AppColors.textOnGlass.withValues(alpha: a);
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
