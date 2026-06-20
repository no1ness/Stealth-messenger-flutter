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

/// Animated blur spots background. Now renders a static gradient for performance.
class StealthAnimatedBackground extends StatelessWidget {
  final Widget child;

  const StealthAnimatedBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return RepaintBoundary(
      child: Container(
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
      ),
    );
  }
}
