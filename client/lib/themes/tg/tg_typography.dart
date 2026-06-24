import 'package:flutter/material.dart';
import 'package:stealth/logging/logger.dart';

class TgTypography {
  TgTypography._();

  static TextStyle get largeTitle => const TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static TextStyle get title1 => const TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static TextStyle get title2 => const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static TextStyle get title3 => const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );

  static TextStyle get headline => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static TextStyle get body => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static TextStyle get bodyEmphasis => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static TextStyle get callout => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static TextStyle get calloutEmphasis => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static TextStyle get subheadline => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static TextStyle get subheadlineEmphasis => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static TextStyle get footnote => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  static TextStyle get footnoteEmphasis => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static TextStyle get caption1 => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.25,
  );

  static TextStyle get caption1Emphasis => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static TextStyle get caption2 => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static TextStyle get caption2Emphasis => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static TextStyle get captionMono => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.25,
    fontFamily: 'RobotoMono',
  );

  static TextStyle get titleMono => const TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFamily: 'RobotoMono',
  );

  static const String fontFamily = 'Roboto';
  static const String fontFamilyMono = 'RobotoMono';

  static TextTheme get textTheme => const TextTheme(
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3),
    titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25),
    titleSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.25),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.4),
    bodyMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.4),
    bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.25),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.3),
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.3),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.2),
  );

  static void init() {
    Logger.info('TgTypography: migrated from Geist to Roboto');
  }
}
