import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Static stealth gradient (no animation). Used where a moving background
/// would distract from the foreground content.
class StealthBackground extends StatelessWidget {
  final Widget child;

  const StealthBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? AppColors.stealthGradientLight
              : AppColors.stealthGradient,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Stealth background with animated blur spots (signature dark-mode look).
///
/// **Theme-aware:** in light mode the animated blur layer is dropped and
/// the widget renders a calm static gradient (per design-system.md, light
/// is the "accessibility / high contrast" mode — effects auto-disable).
/// The animation controller is stopped while the theme is light so the
/// 20-second loop is not consuming a vsync tick for nothing.
///
/// Wrapped in `RepaintBoundary` per the performance-discipline rules — a
/// foreground subtree must not invalidate on every background tick.
class StealthAnimatedBackground extends StatefulWidget {
  final Widget child;

  const StealthAnimatedBackground({
    super.key,
    required this.child,
  });

  @override
  State<StealthAnimatedBackground> createState() =>
      _StealthAnimatedBackgroundState();
}

class _StealthAnimatedBackgroundState extends State<StealthAnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Brightness? _lastBrightness;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness == _lastBrightness) return;
    _lastBrightness = brightness;
    if (brightness == Brightness.dark) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (isLight) {
      return RepaintBoundary(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.stealthGradientLight,
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
            widget.child,
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: Stack(
        children: [
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
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: StealthBlurPainter(
                    animation: _controller.value,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// Paints the three animated blur spots used by [StealthAnimatedBackground]
/// in dark mode. Kept public so tests / golden snapshots can drive it
/// with a fixed `animation` value.
class StealthBlurPainter extends CustomPainter {
  final double animation;

  StealthBlurPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final offset1 = Offset(
      size.width * 0.2 + (size.width * 0.3 * animation),
      size.height * 0.3,
    );
    paint.color = AppColors.systemBlue.withValues(alpha: 0.1);
    canvas.drawCircle(offset1, 150, paint);

    final offset2 = Offset(
      size.width * 0.7 - (size.width * 0.2 * animation),
      size.height * 0.6,
    );
    paint.color = AppColors.systemPurple.withValues(alpha: 0.08);
    canvas.drawCircle(offset2, 200, paint);

    final offset3 = Offset(
      size.width * 0.5,
      size.height * 0.8 - (size.height * 0.3 * animation),
    );
    paint.color = const Color(0xFF1E3A8A).withValues(alpha: 0.12);
    canvas.drawCircle(offset3, 180, paint);
  }

  @override
  bool shouldRepaint(covariant StealthBlurPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
