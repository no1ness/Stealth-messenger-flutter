import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class StealthBackground extends StatelessWidget {
  final Widget child;

  const StealthBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.stealthGradient,
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Анимированный stealth фон с плавающими blur-точками
class StealthAnimatedBackground extends StatefulWidget {
  final Widget child;

  const StealthAnimatedBackground({
    super.key,
    required this.child,
  });

  @override
  State<StealthAnimatedBackground> createState() => _StealthAnimatedBackgroundState();
}

class _StealthAnimatedBackgroundState extends State<StealthAnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
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
        // Базовый градиент
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.stealthGradient,
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        
        // Анимированные blur-пятна для глубины
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: StealthBlurPainter(
                animation: _controller.value,
              ),
              size: Size.infinite,
            );
          },
        ),
        
        // Контент поверх
        widget.child,
      ],
    );
  }
}

/// Рисует анимированные blur-пятна для эффекта глубины
class StealthBlurPainter extends CustomPainter {
  final double animation;

  StealthBlurPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    // Первое пятно (синее)
    final offset1 = Offset(
      size.width * 0.2 + (size.width * 0.3 * animation),
      size.height * 0.3,
    );
    paint.color = AppColors.systemBlue.withOpacity(0.1);
    canvas.drawCircle(offset1, 150, paint);

    // Второе пятно (фиолетовое)
    final offset2 = Offset(
      size.width * 0.7 - (size.width * 0.2 * animation),
      size.height * 0.6,
    );
    paint.color = AppColors.systemPurple.withOpacity(0.08);
    canvas.drawCircle(offset2, 200, paint);

    // Третье пятно (синее темное)
    final offset3 = Offset(
      size.width * 0.5,
      size.height * 0.8 - (size.height * 0.3 * animation),
    );
    paint.color = const Color(0xFF1E3A8A).withOpacity(0.12);
    canvas.drawCircle(offset3, 180, paint);
  }

  @override
  bool shouldRepaint(covariant StealthBlurPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
