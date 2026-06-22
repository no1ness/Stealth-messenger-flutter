import 'package:flutter/material.dart';
import 'tg_colors.dart';

class TgThemeData {
  TgThemeData._();

  static ThemeData get light {
    final c = _lightColors;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: c.primary,
        onPrimary: Colors.white,
        secondary: c.primary,
        onSecondary: Colors.white,
        surface: c.background,
        onSurface: c.text,
        error: c.error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: c.background,
      appBarTheme: AppBarTheme(
        backgroundColor: c.backgroundSecondary,
        foregroundColor: c.text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: c.text,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.backgroundSecondary,
        labelStyle: TextStyle(color: c.text, fontSize: 14),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.backgroundSecondary,
        selectedItemColor: c.primary,
        unselectedItemColor: c.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.backgroundSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.bordersInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.bordersInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        hintStyle: TextStyle(color: c.textSecondary, fontSize: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.toastBackground,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.gray;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary.withValues(alpha: 0.4);
          return c.gray.withValues(alpha: 0.3);
        }),
      ),
      dividerColor: c.dividers,
      dividerTheme: DividerThemeData(
        color: c.dividers,
        thickness: 0.5,
      ),
    );
  }

  static ThemeData get dark {
    final c = _darkColors;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: c.primary,
        onPrimary: Colors.white,
        secondary: c.primary,
        onSecondary: Colors.white,
        surface: c.background,
        onSurface: c.text,
        error: c.error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: c.background,
      appBarTheme: AppBarTheme(
        backgroundColor: c.backgroundSecondary,
        foregroundColor: c.text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: c.text,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.backgroundSecondary,
        labelStyle: TextStyle(color: c.text, fontSize: 14),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.backgroundSecondary,
        selectedItemColor: c.primary,
        unselectedItemColor: c.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.backgroundSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.bordersInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.bordersInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        hintStyle: TextStyle(color: c.textSecondary, fontSize: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.toastBackground,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.gray;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary.withValues(alpha: 0.4);
          return c.gray.withValues(alpha: 0.3);
        }),
      ),
      dividerColor: c.dividers,
      dividerTheme: DividerThemeData(
        color: c.dividers,
        thickness: 0.5,
      ),
    );
  }

  /// Direct color instances for theme construction without BuildContext.
  static TgThemeColors get _lightColors => TgThemeColors.light;
  static TgThemeColors get _darkColors => TgThemeColors.dark;
}
