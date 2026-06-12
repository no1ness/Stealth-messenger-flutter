import 'package:flutter/material.dart';
import 'constants/app_colors.dart';
import 'constants/app_typography.dart';
import 'constants/app_spacing.dart';

class LiquidTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,

        // Color Scheme
        colorScheme: const ColorScheme.light(
          primary: AppColors.systemBlue,
          secondary: AppColors.systemPurple,
          surface: AppColors.systemGray6,
          error: AppColors.systemRed,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.black,
          onError: Colors.white,
        ),

        // Scaffold
        scaffoldBackgroundColor: AppColors.systemGray6,

        // App Bar Theme
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.systemGray6,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(
            color: AppColors.systemBlue,
          ),
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),

        // Text Theme
        textTheme: const TextTheme(
          displayLarge: AppTypography.largeTitle,
          displayMedium: AppTypography.title1,
          displaySmall: AppTypography.title2,
          headlineMedium: AppTypography.title3,
          headlineSmall: AppTypography.headline,
          bodyLarge: AppTypography.body,
          bodyMedium: AppTypography.callout,
          bodySmall: AppTypography.subheadline,
          labelLarge: AppTypography.footnote,
          labelMedium: AppTypography.caption1,
          labelSmall: AppTypography.caption2,
        ).apply(
          bodyColor: Colors.black,
          displayColor: Colors.black,
        ),

        // Icon Theme
        iconTheme: const IconThemeData(
          color: AppColors.systemGray,
          size: AppSpacing.iconMd,
        ),

        // Card Theme
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
        ),

        // Input Decoration Theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.systemGray5,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: const BorderSide(
              color: AppColors.systemBlue,
              width: 2,
            ),
          ),
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.systemGray,
          ),
        ),

        // Button Theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.systemBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),

        // Divider Theme
        dividerTheme: const DividerThemeData(
          color: AppColors.systemGray4,
          thickness: 0.5,
          space: 1,
        ),

        // Bottom Navigation Bar Theme
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: AppColors.systemBlue,
          unselectedItemColor: AppColors.systemGray,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,

        // Color Scheme
        colorScheme: const ColorScheme.dark(
          primary: AppColors.systemBlueDark,
          secondary: AppColors.systemPurple,
          surface: AppColors.darkGray,
          error: AppColors.systemRed,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onError: Colors.white,
        ),

        // Scaffold
        scaffoldBackgroundColor: AppColors.backgroundPrimary,

        // App Bar Theme
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(
            color: AppColors.systemBlueDark,
          ),
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),

        // Text Theme
        textTheme: const TextTheme(
          displayLarge: AppTypography.largeTitle,
          displayMedium: AppTypography.title1,
          displaySmall: AppTypography.title2,
          headlineMedium: AppTypography.title3,
          headlineSmall: AppTypography.headline,
          bodyLarge: AppTypography.body,
          bodyMedium: AppTypography.callout,
          bodySmall: AppTypography.subheadline,
          labelLarge: AppTypography.footnote,
          labelMedium: AppTypography.caption1,
          labelSmall: AppTypography.caption2,
        ).apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),

        // Icon Theme
        iconTheme: const IconThemeData(
          color: AppColors.textSecondary,
          size: AppSpacing.iconMd,
        ),

        // Card Theme
        cardTheme: CardThemeData(
          color: AppColors.darkGray2,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
        ),

        // Input Decoration Theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkGray3,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: const BorderSide(
              color: AppColors.systemBlueDark,
              width: 2,
            ),
          ),
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.systemGray,
          ),
        ),

        // Button Theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.systemBlueDark,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),

        // Divider Theme
        dividerTheme: const DividerThemeData(
          color: AppColors.darkGray4,
          thickness: 0.5,
          space: 1,
        ),

        // Bottom Navigation Bar Theme
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkGray,
          elevation: 0,
          selectedItemColor: AppColors.systemBlueDark,
          unselectedItemColor: AppColors.systemGray,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
      );
}
