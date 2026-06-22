import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_motion.dart';
import '../constants/app_spacing.dart';
import '../constants/glass_styles.dart';

enum GlassIntensity {
  ultraLight,
  light,
  medium,
  dark,
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final GlassIntensity intensity;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final VoidCallback? onTap;
  final List<Color>? gradient;
  final double blur;

  const GlassContainer({
    super.key,
    required this.child,
    this.intensity = GlassIntensity.medium,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.gradient,
    this.blur = AppSpacing.glassBlur,
  });

  /// Per design-system.md (Dual identity): in light mode every glass
  /// surface drops the white tint + coloured glow and uses a faint
  /// black-tinted film with a single hairline shadow. Same geometry,
  /// noticeably lower intensity — appropriate over a near-white scaffold.
  BoxDecoration _getDecoration(Brightness brightness) {
    if (gradient != null) {
      return GlassStyles.glassWithGradient(gradient!);
    }

    final isLight = brightness == Brightness.light;
    switch (intensity) {
      case GlassIntensity.ultraLight:
        return isLight
            ? GlassStyles.ultraLightGlassLight
            : GlassStyles.ultraLightGlass;
      case GlassIntensity.light:
        return isLight ? GlassStyles.lightGlassLight : GlassStyles.lightGlass;
      case GlassIntensity.medium:
        return isLight ? GlassStyles.mediumGlassLight : GlassStyles.mediumGlass;
      case GlassIntensity.dark:
        return isLight ? GlassStyles.darkGlassLight : GlassStyles.darkGlass;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final container = ClipRRect(
      borderRadius: BorderRadius.circular(
        borderRadius ?? AppSpacing.radiusLg,
      ),
      child: RepaintBoundary(
        child: Container(
            width: width,
            height: height,
            padding: padding ?? const EdgeInsets.all(AppSpacing.md),
            margin: margin,
            decoration: _getDecoration(brightness),
            child: child,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: container,
      );
    }

    return container;
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double? borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      intensity: GlassIntensity.light,
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      margin: margin ?? const EdgeInsets.all(AppSpacing.cardMargin),
      borderRadius: borderRadius ?? AppSpacing.radiusXl,
      onTap: onTap,
      blur: AppSpacing.glassBlur,
      child: child,
    );
  }
}

class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final List<Color>? gradient;
  final bool isPrimary;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.padding,
    this.width,
    this.height,
    this.gradient,
    this.isPrimary = false,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppMotion.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? _handleTapDown : null,
      onTapUp: widget.onPressed != null ? _handleTapUp : null,
      onTapCancel: widget.onPressed != null ? _handleTapCancel : null,
      onTap: widget.onPressed,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: RepaintBoundary(
            child: Container(
                width: widget.width,
                height: widget.height ?? AppSpacing.buttonHeightMedium,
                padding: widget.padding ??
                    const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.sm,
                    ),
                decoration: widget.isPrimary
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.gradient ?? AppColors.liquidGradient1,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(
                          color: AppColors.glassLight.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (widget.gradient ?? AppColors.liquidGradient1)
                                    .first
                                    .withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 0,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      )
                    : GlassStyles.buttonGlass,
                child: Center(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}
