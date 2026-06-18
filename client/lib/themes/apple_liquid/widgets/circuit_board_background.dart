import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Фон в стиле микросхем/печатной платы (circuit board)
class CircuitBoardBackground extends StatefulWidget {
  final Widget child;
  final bool animated;

  const CircuitBoardBackground({
    super.key,
    required this.child,
    this.animated = true,
  });

  @override
  State<CircuitBoardBackground> createState() => _CircuitBoardBackgroundState();
}

class _CircuitBoardBackgroundState extends State<CircuitBoardBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _controller = AnimationController(
        duration: const Duration(seconds: 30),
        vsync: this,
      )..repeat();
    } else {
      _controller = AnimationController(vsync: this);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF050812),
                Color(0xFF0A0E1A),
                Color(0xFF0D1117),
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),

        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: CircuitBoardPainter(
                  animation: widget.animated ? _controller.value : 0.0,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),

        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.0,
              colors: [
                Colors.transparent,
                const Color(0xFF0A0E1A).withValues(alpha: 0.5),
              ],
            ),
          ),
        ),

        widget.child,
      ],
    );
  }
}

class _SizeKey {
  const _SizeKey(this.w, this.h);
  final double w, h;
  @override
  bool operator ==(Object other) =>
      other is _SizeKey && w == other.w && h == other.h;
  @override
  int get hashCode => Object.hash(w, h);
}

class CircuitBoardPainter extends CustomPainter {
  final double animation;

  CircuitBoardPainter({required this.animation});

  static final Map<_SizeKey, ui.Picture> _staticCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final key = _SizeKey(size.width, size.height);
    final cached = _staticCache[key];
    if (cached == null) {
      final recorder = ui.PictureRecorder();
      final cacheCanvas = Canvas(recorder);
      _paintStatic(cacheCanvas, size);
      final picture = recorder.endRecording();
      _staticCache[key] = picture;
      canvas.drawPicture(picture);
    } else {
      canvas.drawPicture(cached);
    }

    _paintAnimated(canvas, size);
  }

  void _paintStatic(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final dotPaint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);

    final lineColor = const Color(0xFF1E3A8A).withValues(alpha: 0.3);
    final accentColor = const Color(0xFF3B82F6).withValues(alpha: 0.15);
    final glowColor = const Color(0xFF60A5FA).withValues(alpha: 0.1);

    for (int i = 0; i < 12; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final w = 30 + random.nextDouble() * 40;
      final h = 20 + random.nextDouble() * 30;
      final chipRect = Rect.fromLTWH(x, y, w, h);

      paint.color = const Color(0xFF1E3A8A).withValues(alpha: 0.2);
      paint.style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3)), paint);

      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 1.5;
      paint.color = const Color(0xFF3B82F6).withValues(alpha: 0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3)), paint);

      paint.strokeWidth = 0.8;
      for (int j = 0; j < 8; j++) {
        final pinY = y + (h / 9) * (j + 1);
        canvas.drawLine(Offset(x - 5, pinY), Offset(x, pinY), paint);
        canvas.drawLine(Offset(x + w, pinY), Offset(x + w + 5, pinY), paint);
      }
    }

    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.5;
    for (int i = 0; i < 25; i++) {
      final startX = random.nextDouble() * size.width;
      final startY = random.nextDouble() * size.height;
      final endX = startX + (random.nextDouble() - 0.5) * 150;
      final endY = startY + (random.nextDouble() - 0.5) * 150;

      paint.shader = LinearGradient(
        colors: [lineColor, accentColor, lineColor],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(
        Rect.fromLTWH(startX, startY, endX - startX, endY - startY));

      final midX = startX + (endX - startX) * 0.7;
      canvas.drawLine(Offset(startX, startY), Offset(midX, startY), paint);
      canvas.drawLine(Offset(midX, startY), Offset(midX, endY), paint);
      canvas.drawLine(Offset(midX, endY), Offset(endX, endY), paint);
    }

    paint.shader = null;

    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;

      dotPaint.color = glowColor.withValues(alpha: 0.3);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);

      dotPaint.color = accentColor.withValues(alpha: 0.3);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);

      dotPaint.color =
          const Color(0xFF60A5FA).withValues(alpha: 0.3);
      canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
    }
  }

  void _paintAnimated(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final lineColor = const Color(0xFF1E3A8A).withValues(alpha: 0.3);
    final accentColor = const Color(0xFF3B82F6).withValues(alpha: 0.15);
    final glowColor = const Color(0xFF60A5FA).withValues(alpha: 0.1);
    final anim = animation;

    for (int i = 0; i < 20; i++) {
      final y = (size.height / 20) * i;
      final offset = math.sin(anim * math.pi * 2 + i * 0.5) * 10;

      paint.color = i % 3 == 0 ? accentColor : lineColor;
      canvas.drawLine(
        Offset(0, y + offset), Offset(size.width, y + offset), paint);

      paint.strokeWidth = 0.5;
      paint.color = lineColor.withValues(alpha: 0.5);
      canvas.drawLine(
        Offset(0, y + offset + 2), Offset(size.width, y + offset + 2), paint);
      paint.strokeWidth = 1.0;
    }

    for (int i = 0; i < 30; i++) {
      final x = (size.width / 30) * i;
      final offset = math.cos(anim * math.pi * 2 + i * 0.3) * 15;
      paint.color = i % 4 == 0 ? accentColor : lineColor;
      canvas.drawLine(
        Offset(x + offset, 0), Offset(x + offset, size.height), paint);
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final pulsePhase = (anim + (i * 0.02)) % 1.0;
      final pulseOpacity = 0.2 + (math.sin(pulsePhase * math.pi * 2) * 0.1);

      dotPaint.color = glowColor.withValues(alpha: pulseOpacity * 0.5);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);

      dotPaint.color = accentColor.withValues(alpha: pulseOpacity);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);

      dotPaint.color =
          const Color(0xFF60A5FA).withValues(alpha: pulseOpacity * 1.5);
      canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CircuitBoardPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
