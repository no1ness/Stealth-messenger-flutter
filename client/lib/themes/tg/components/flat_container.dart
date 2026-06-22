import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

enum FlatIntensity { ultraLight, light, medium, dark }

class FlatContainer extends StatelessWidget {
  final Widget child;
  final FlatIntensity intensity;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final VoidCallback? onTap;
  final Color? color;

  const FlatContainer({
    super.key,
    required this.child,
    this.intensity = FlatIntensity.medium,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.color,
  });

  Color _getColor(BuildContext context) {
    if (color != null) return color!;
    final c = TgThemeColors.of(context);
    switch (intensity) {
      case FlatIntensity.ultraLight:
        return c.background;
      case FlatIntensity.light:
        return c.cardBackground;
      case FlatIntensity.medium:
        return c.surface;
      case FlatIntensity.dark:
        return c.backgroundSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final container = ClipRRect(
      borderRadius: BorderRadius.circular(
        borderRadius ?? TgSpacing.radiusLg,
      ),
      child: Container(
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.all(TgSpacing.md),
        margin: margin,
        decoration: BoxDecoration(
          color: _getColor(context),
          borderRadius: BorderRadius.circular(
            borderRadius ?? TgSpacing.radiusLg,
          ),
        ),
        child: child,
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: container);
    }

    return container;
  }
}

class FlatCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double? borderRadius;

  const FlatCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Card(
      color: c.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          borderRadius ?? TgSpacing.radiusXl,
        ),
      ),
      margin: margin ?? EdgeInsets.all(TgSpacing.sm),
      child: Padding(
        padding: padding ?? EdgeInsets.all(TgSpacing.md),
        child: child,
      ),
    );
  }
}

class FlatButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool isPrimary;

  const FlatButton({
    super.key,
    required this.child,
    this.onPressed,
    this.padding,
    this.width,
    this.height,
    this.isPrimary = false,
  });

  @override
  State<FlatButton> createState() => _FlatButtonState();
}

class _FlatButtonState extends State<FlatButton> {
  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return SizedBox(
      width: widget.width,
      height: widget.height ?? TgSpacing.buttonHeight,
      child: ElevatedButton(
        onPressed: widget.onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.isPrimary ? c.primary : c.surface,
          foregroundColor: widget.isPrimary ? Colors.white : c.text,
          elevation: 0,
          padding: widget.padding ?? EdgeInsets.symmetric(
            horizontal: TgSpacing.xl,
            vertical: TgSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TgSpacing.radiusMd),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
