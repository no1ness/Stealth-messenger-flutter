import 'package:flutter/material.dart';

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
    final isDark = brightness == Brightness.dark;
    if (!isDark && !force) return child;

    return RepaintBoundary(
      child: Stack(
        children: [
          child,
          CustomPaint(
            painter: _ScanlinePainter(intensity: intensity),
            size: Size.infinite,
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
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03 * intensity)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) =>
      intensity != oldDelegate.intensity;
}
