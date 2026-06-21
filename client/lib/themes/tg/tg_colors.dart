import 'package:flutter/material.dart';

class TgColors {
  TgColors._();

  static final Map<int, TgColors> _instances = {};

  static TgColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return _instances.putIfAbsent(
      brightness.index,
      () => TgColors._fromBrightness(brightness),
    );
  }

  factory TgColors._fromBrightness(Brightness brightness) {
    if (brightness == Brightness.light) return TgColors._light();
    return TgColors._dark();
  }

  factory TgColors._light() {
    return TgColors._(
      text: const Color(0xFF0A0E1A),
      textSecondary: const Color(0x990A0E1A),
      surface: const Color(0xFFF5F5F7),
      divider: const Color(0x0D000000),
      accent: const Color(0xFF007AFF),
      background: const Color(0xFFF5F5F7),
      cardBackground: Colors.white,
    );
  }

  factory TgColors._dark() {
    return TgColors._(
      text: const Color(0xFFFFFFFF),
      textSecondary: const Color(0x99FFFFFF),
      surface: const Color(0xFF151922),
      divider: const Color(0x29FFFFFF),
      accent: const Color(0xFF0A84FF),
      background: const Color(0xFF0A0E1A),
      cardBackground: const Color(0xFF151922),
    );
  }

  const TgColors._({
    required this.text,
    required this.textSecondary,
    required this.surface,
    required this.divider,
    required this.accent,
    required this.background,
    required this.cardBackground,
  });

  final Color text;
  final Color textSecondary;
  final Color surface;
  final Color divider;
  final Color accent;
  final Color background;
  final Color cardBackground;
}
