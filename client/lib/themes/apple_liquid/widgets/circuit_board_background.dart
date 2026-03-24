import 'dart:math' as math;
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
        // Базовый градиент (темный фон)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF050812), // Очень темный синий
                Color(0xFF0A0E1A), // Темно-синеватый
                Color(0xFF0D1117), // Очень темный
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),

        // Circuit board паттерн
        AnimatedBuilder(
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

        // Subtle gradient overlay для глубины
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

        // Контент поверх
        widget.child,
      ],
    );
  }
}

/// Рисует паттерн печатной платы с линиями и точками
class CircuitBoardPainter extends CustomPainter {
  final double animation;

  CircuitBoardPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final dotPaint = Paint()..style = PaintingStyle.fill;

    final random = math.Random(42); // Фиксированный seed для консистентности

    // Цвета для circuit lines
    final lineColor = const Color(0xFF1E3A8A).withValues(alpha: 0.3); // Темно-синий
    final accentColor = const Color(0xFF3B82F6).withValues(alpha: 0.15); // Синий
    final glowColor = const Color(0xFF60A5FA).withValues(alpha: 0.1); // Светло-синий

    // Рисуем горизонтальные линии
    for (int i = 0; i < 20; i++) {
      final y = (size.height / 20) * i;
      final offset = math.sin(animation * math.pi * 2 + i * 0.5) * 10;
      
      paint.color = i % 3 == 0 ? accentColor : lineColor;
      
      // Главная линия
      canvas.drawLine(
        Offset(0, y + offset),
        Offset(size.width, y + offset),
        paint,
      );

      // Параллельная thin линия для эффекта PCB
      paint.strokeWidth = 0.5;
      paint.color = lineColor.withValues(alpha: 0.5);
      canvas.drawLine(
        Offset(0, y + offset + 2),
        Offset(size.width, y + offset + 2),
        paint,
      );
      paint.strokeWidth = 1.0;
    }

    // Рисуем вертикальные линии
    for (int i = 0; i < 30; i++) {
      final x = (size.width / 30) * i;
      final offset = math.cos(animation * math.pi * 2 + i * 0.3) * 15;
      
      paint.color = i % 4 == 0 ? accentColor : lineColor;
      
      canvas.drawLine(
        Offset(x + offset, 0),
        Offset(x + offset, size.height),
        paint,
      );
    }

    // Рисуем "чипы" (прямоугольники)
    for (int i = 0; i < 12; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final width = 30 + random.nextDouble() * 40;
      final height = 20 + random.nextDouble() * 30;

      final chipRect = Rect.fromLTWH(x, y, width, height);
      
      // Корпус чипа
      paint.color = const Color(0xFF1E3A8A).withValues(alpha: 0.2);
      paint.style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3)),
        paint,
      );

      // Обводка чипа
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 1.5;
      paint.color = const Color(0xFF3B82F6).withValues(alpha: 0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3)),
        paint,
      );

      // "Ножки" чипа (pins)
      paint.strokeWidth = 0.8;
      for (int j = 0; j < 8; j++) {
        final pinY = y + (height / 9) * (j + 1);
        // Левые ножки
        canvas.drawLine(
          Offset(x - 5, pinY),
          Offset(x, pinY),
          paint,
        );
        // Правые ножки
        canvas.drawLine(
          Offset(x + width, pinY),
          Offset(x + width + 5, pinY),
          paint,
        );
      }
    }

    // Рисуем соединительные точки (vias)
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      
      // Анимированное свечение
      final pulsePhase = (animation + (i * 0.02)) % 1.0;
      final pulseOpacity = 0.2 + (math.sin(pulsePhase * math.pi * 2) * 0.1);

      // Внешний glow
      dotPaint.color = glowColor.withValues(alpha: pulseOpacity * 0.5);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);

      // Средний круг
      dotPaint.color = accentColor.withValues(alpha: pulseOpacity);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);

      // Внутренний яркий центр
      dotPaint.color = const Color(0xFF60A5FA).withValues(alpha: pulseOpacity * 1.5);
      canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
    }

    // Рисуем traces (дорожки) между точками
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.5;
    for (int i = 0; i < 25; i++) {
      final startX = random.nextDouble() * size.width;
      final startY = random.nextDouble() * size.height;
      final endX = startX + (random.nextDouble() - 0.5) * 150;
      final endY = startY + (random.nextDouble() - 0.5) * 150;

      final gradient = LinearGradient(
        colors: [
          lineColor,
          accentColor,
          lineColor,
        ],
        stops: const [0.0, 0.5, 1.0],
      );

      paint.shader = gradient.createShader(
        Rect.fromLTWH(startX, startY, endX - startX, endY - startY),
      );

      // Рисуем L-образную дорожку (как на PCB)
      final midX = startX + (endX - startX) * 0.7;
      canvas.drawLine(Offset(startX, startY), Offset(midX, startY), paint);
      canvas.drawLine(Offset(midX, startY), Offset(midX, endY), paint);
      canvas.drawLine(Offset(midX, endY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CircuitBoardPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
