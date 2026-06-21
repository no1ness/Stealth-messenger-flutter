import 'package:flutter/material.dart';
import 'tg_colors.dart';

class TgThemeData {
  TgThemeData._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: const Color(0xFF007AFF),
      onPrimary: Colors.white,
      secondary: const Color(0xFF007AFF),
      onSecondary: Colors.white,
      surface: const Color(0xFFF5F5F7),
      onSurface: const Color(0xFF0A0E1A),
      error: const Color(0xFFFF3B30),
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F5F7),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: const Color(0xFF0A84FF),
      onPrimary: Colors.white,
      secondary: const Color(0xFF0A84FF),
      onSecondary: Colors.white,
      surface: const Color(0xFF151922),
      onSurface: Colors.white,
      error: const Color(0xFFFF453A),
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFF0A0E1A),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  );
}
