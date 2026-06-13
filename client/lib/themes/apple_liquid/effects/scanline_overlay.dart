import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_effects.dart';

/// Signature horizontal scan-line overlay.
///
/// Renders thin horizontal stripes over [child] at the spacing /
/// thickness / opacity defined in [AppEffects]. Multiplies the
/// alpha by [intensity] so callers can dial the effect down for
/// secondary surfaces (the chat-bubble usage runs at `0.5`; the
/// `DialogImportance.high` body uses the full `1.0`).
///
/// **Theme-aware gating.** In [Brightness.light] the overlay
/// renders [child] unchanged — light mode is the "accessibility /
/// high contrast" face of the app and deliberately skips signature
/// ornaments. Pass `force: true` to bypass the gate; this should
/// only be used by tests that need to inspect the painted lines.
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.force = false,
  });

  final Widget child;
  final double intensity;
  final bool force;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.light && !force) {
      // Light mode: skip the overlay entirely. Logging once at
      // mount makes it easy to verify in dev that the gate is
      // firing as expected.
      debugPrint(
        '[fx:scanline] gated-out brightness=light intensity=$intensity',
      );
      return child;
    }
    debugPrint(
      '[fx:scanline] mount brightness=$brightness intensity=$intensity',
    );
    return RepaintBoundary(
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScanlinePainter(intensity: intensity),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter({required this.intensity});

  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = (AppEffects.scanlineOpacity * intensity).clamp(0.0, 1.0);
    if (alpha <= 0) {
      return;
    }
    final paint = Paint()
      ..color = AppColors.textOnGlass.withValues(alpha: alpha)
      ..strokeWidth = AppEffects.scanlineThicknessPx
      ..style = PaintingStyle.stroke;

    final spacing = AppEffects.scanlineSpacingPx;
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) =>
      oldDelegate.intensity != intensity;
}
