import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

class GlassStyles {
  GlassStyles._();

  // Glass container decorations with different opacity levels

  // Ultra light glass (strongest effect) with stealth blue glow
  static BoxDecoration get ultraLightGlass => BoxDecoration(
        color: AppColors.glassLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.glassLight.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.systemBlue.withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          ),
        ],
      );

  // Light glass with stealth blue tint
  static BoxDecoration get lightGlass => BoxDecoration(
        color: AppColors.glassMedium,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.glassMedium.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: AppColors.glassBlue,
            blurRadius: 25,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          ),
        ],
      );

  // Medium glass (balanced) with subtle stealth glow
  static BoxDecoration get mediumGlass => BoxDecoration(
        color: AppColors.glassDark,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.glassMedium.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: AppColors.glassBlue,
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          ),
        ],
      );

  // Dark glass (subtle effect) with purple stealth tint
  static BoxDecoration get darkGlass => BoxDecoration(
        color: AppColors.glassUltraDark,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.glassDark,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: AppColors.glassPurple,
            blurRadius: 15,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          ),
        ],
      );

  // Card glass with strong shadow
  static BoxDecoration get cardGlass => BoxDecoration(
        color: AppColors.glassMedium,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(
          color: AppColors.glassLight.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowStrong,
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      );

  // Gradient glass overlays
  static BoxDecoration glassWithGradient(List<Color> gradientColors) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors.map((c) => c.withValues(alpha: 0.3)).toList(),
      ),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(
        color: AppColors.glassLight.withValues(alpha: 0.3),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: gradientColors.first.withValues(alpha: 0.3),
          blurRadius: 20,
          spreadRadius: 0,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // Frosted glass (with backdrop blur effect indicator)
  static BoxDecoration get frostedGlass => BoxDecoration(
        color: AppColors.glassMedium,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(
          color: AppColors.glassLight.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowStrong,
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 12),
          ),
        ],
      );

  // Elevated glass (for floating elements)
  static BoxDecoration get elevatedGlass => BoxDecoration(
        color: AppColors.glassLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.glassLight.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowStrong,
            blurRadius: 40,
            spreadRadius: -5,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      );

  // Button glass
  static BoxDecoration get buttonGlass => BoxDecoration(
        color: AppColors.glassMedium,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.glassLight.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      );

  // Tab bar glass
  static BoxDecoration get tabBarGlass => BoxDecoration(
        color: AppColors.darkGray2.withValues(alpha: 0.8),
        border: const Border(
          top: BorderSide(
            color: AppColors.separator,
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, -2),
          ),
        ],
      );

  // Utility methods
  static BoxDecoration customGlass({
    Color? color,
    double borderRadius = AppSpacing.radiusLg,
    Color? borderColor,
    double borderWidth = 1.0,
    double blurRadius = 16.0,
    double shadowOpacity = 0.2,
  }) {
    return BoxDecoration(
      color: color ?? AppColors.glassMedium,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? AppColors.glassLight.withValues(alpha: 0.3),
        width: borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: shadowOpacity),
          blurRadius: blurRadius,
          spreadRadius: 0,
          offset: Offset(0, blurRadius / 4),
        ),
      ],
    );
  }
}
