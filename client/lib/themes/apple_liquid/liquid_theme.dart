import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'constants/app_colors.dart';
import 'constants/app_motion.dart';
import 'constants/app_spacing.dart';
import 'constants/app_typography.dart';

/// The two Stealth `ThemeData` instances — the dark face (signature
/// "refined crypto-noir") and the light face ("accessibility / high
/// contrast" mode).
///
/// Every Material slot we ship widgets through is wired here so that
/// stock components (`FilledButton`, `TextField`, `Tooltip`,
/// `PopupMenu`, `CircularProgressIndicator`, `FloatingActionButton`)
/// inherit the Stealth aesthetic without per-call-site overrides.
/// New screens should reach for stock Material first; only fall back
/// to bespoke surfaces (e.g. `GlassContainer`) when the design
/// genuinely needs glass.
///
/// Light vs dark is NOT a simple palette inversion — see
/// `docs/design-system.md > Dual identity`:
///
/// - **Dark** is the signature. Background flows through
///   [AppColors.backgroundPrimary]. Surfaces are translucent glass.
///   Signature scan-line / grain effects auto-enable.
/// - **Light** is deliberately lower-key. Same accent palette but
///   on near-white surfaces with stronger borders for contrast.
///   Signature effects auto-disable (see overlay widgets in
///   `effects/`).
class LiquidTheme {
  LiquidTheme._();

  // ===== Shared sub-themes ======================================

  /// Text theme used by both light and dark. The base styles live
  /// in [AppTypography] (Geist Sans body, Geist Mono numerics);
  /// the per-theme colour overrides are applied below via `.apply`.
  static const TextTheme _baseTextTheme = TextTheme(
    displayLarge: AppTypography.largeTitle,
    displayMedium: AppTypography.title1,
    displaySmall: AppTypography.title2,
    headlineMedium: AppTypography.title3,
    headlineSmall: AppTypography.headline,
    titleLarge: AppTypography.title3,
    titleMedium: AppTypography.headline,
    titleSmall: AppTypography.calloutEmphasis,
    bodyLarge: AppTypography.body,
    bodyMedium: AppTypography.callout,
    bodySmall: AppTypography.subheadline,
    labelLarge: AppTypography.footnoteEmphasis,
    labelMedium: AppTypography.caption1,
    labelSmall: AppTypography.caption2,
  );

  /// Page-transition theme tied to [AppMotion.pageRoute]. Stock
  /// `MaterialPageRoute` instances pick this up so they feel
  /// consistent with `GlassPageRoute`.
  static const PageTransitionsTheme _pageTransitions =
      PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
  });

  // ===== Light theme ============================================

  static ThemeData get theme {
    final cs = const ColorScheme.light(
      primary: AppColors.systemBlue,
      onPrimary: AppColors.textOnGlass,
      secondary: AppColors.systemBlue,
      onSecondary: AppColors.textOnGlass,
      surface: Color(0xFFF5F5F7),
      onSurface: Color(0xFF0A0E1A),
      error: AppColors.statusDanger,
      onError: AppColors.textOnGlass,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: cs,
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      canvasColor: const Color(0xFFF5F5F7),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: _pageTransitions,
      fontFamily: AppTypography.fontFamily,

      textTheme: _baseTextTheme.apply(
        bodyColor: cs.onSurface,
        displayColor: cs.onSurface,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: cs.primary),
        titleTextStyle: AppTypography.headline.copyWith(color: cs.onSurface),
      ),

      iconTheme: IconThemeData(
        color: cs.onSurface.withValues(alpha: 0.75),
        size: AppSpacing.iconMd,
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(
            color: cs.onSurface.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        titleTextStyle: AppTypography.headline.copyWith(color: cs.onSurface),
        contentTextStyle: AppTypography.body.copyWith(color: cs.onSurface),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide:
              BorderSide(color: cs.onSurface.withValues(alpha: 0.12), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide:
              BorderSide(color: cs.onSurface.withValues(alpha: 0.12), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(
            color: AppColors.systemBlue,
            width: 1.5,
          ),
        ),
        hintStyle: AppTypography.body
            .copyWith(color: cs.onSurface.withValues(alpha: 0.45)),
        labelStyle: AppTypography.subheadline
            .copyWith(color: cs.onSurface.withValues(alpha: 0.75)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(style: _filledStyle()),
      filledButtonTheme: FilledButtonThemeData(style: _filledStyle()),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.systemBlue,
          side: BorderSide(color: AppColors.systemBlue.withValues(alpha: 0.6)),
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          shape: _roundedShape,
          textStyle: AppTypography.bodyEmphasis,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.systemBlue,
          minimumSize: const Size(0, AppSpacing.buttonHeightSmall),
          textStyle: AppTypography.callout,
          shape: _roundedShape,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0x14000000),
        thickness: 0.5,
        space: 1,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F2E).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: AppTypography.caption1.copyWith(color: AppColors.textOnGlass),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        waitDuration: AppMotion.slow,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        elevation: 4,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
        textStyle: AppTypography.body.copyWith(color: cs.onSurface),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.systemBlue,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.systemBlue,
        foregroundColor: AppColors.textOnGlass,
        elevation: 4,
        shape: _roundedShape,
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.systemBlue,
        selectionColor: AppColors.systemBlue.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.systemBlue,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        selectedItemColor: AppColors.systemBlue,
        unselectedItemColor: AppColors.systemGray,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: AppTypography.caption2Emphasis,
        unselectedLabelStyle: AppTypography.caption2,
      ),

      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF1A1F2E),
        contentTextStyle: AppTypography.body,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        side:
            BorderSide(color: cs.onSurface.withValues(alpha: 0.12), width: 1),
        labelStyle: AppTypography.caption1.copyWith(color: cs.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
        ),
      ),
    );
  }

  // ===== Dark theme — signature crypto-noir ====================

  static ThemeData get darkTheme {
    final cs = const ColorScheme.dark(
      primary: AppColors.systemBlue,
      onPrimary: AppColors.textOnGlass,
      secondary: AppColors.systemBlue,
      onSecondary: AppColors.textOnGlass,
      surface: AppColors.backgroundSecondary,
      onSurface: AppColors.textOnGlass,
      error: AppColors.statusDanger,
      onError: AppColors.textOnGlass,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: AppColors.backgroundPrimary,
      canvasColor: AppColors.backgroundPrimary,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: _pageTransitions,
      fontFamily: AppTypography.fontFamily,

      textTheme: _baseTextTheme.apply(
        bodyColor: AppColors.textOnGlass,
        displayColor: AppColors.textOnGlass,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.systemBlue),
        titleTextStyle:
            AppTypography.headline.copyWith(color: AppColors.textOnGlass),
      ),

      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: AppSpacing.iconMd,
      ),

      cardTheme: CardThemeData(
        color: AppColors.backgroundSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: const BorderSide(color: AppColors.glassMedium, width: 1),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: const BorderSide(color: AppColors.glassMedium, width: 1),
        ),
        titleTextStyle:
            AppTypography.headline.copyWith(color: AppColors.textOnGlass),
        contentTextStyle:
            AppTypography.body.copyWith(color: AppColors.textOnGlass),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.glassMedium, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.glassMedium, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide:
              const BorderSide(color: AppColors.systemBlue, width: 1.5),
        ),
        hintStyle:
            AppTypography.body.copyWith(color: AppColors.textTertiary),
        labelStyle:
            AppTypography.subheadline.copyWith(color: AppColors.textSecondary),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(style: _filledStyle()),
      filledButtonTheme: FilledButtonThemeData(style: _filledStyle()),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.systemBlue,
          side: const BorderSide(color: AppColors.systemBlue),
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          shape: _roundedShape,
          textStyle: AppTypography.bodyEmphasis,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.systemBlue,
          minimumSize: const Size(0, AppSpacing.buttonHeightSmall),
          textStyle: AppTypography.callout,
          shape: _roundedShape,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.dividerSubtle,
        thickness: 0.5,
        space: 1,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.backgroundTertiary.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: AppColors.glassMedium,
            width: 1,
          ),
        ),
        textStyle: AppTypography.caption1.copyWith(color: AppColors.textOnGlass),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        waitDuration: AppMotion.slow,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.backgroundSecondary,
        elevation: 8,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: AppColors.glassMedium),
        ),
        textStyle: AppTypography.body.copyWith(color: AppColors.textOnGlass),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.systemBlue,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.systemBlue,
        foregroundColor: AppColors.textOnGlass,
        elevation: 6,
        shape: _roundedShape,
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.systemBlue,
        selectionColor: AppColors.systemBlue.withValues(alpha: 0.32),
        selectionHandleColor: AppColors.systemBlue,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppColors.systemBlue,
        unselectedItemColor: AppColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: AppTypography.caption2Emphasis,
        unselectedLabelStyle: AppTypography.caption2,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.backgroundSecondary,
        contentTextStyle:
            AppTypography.body.copyWith(color: AppColors.textOnGlass),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: const BorderSide(color: AppColors.glassMedium, width: 1),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.glassMedium.withValues(alpha: 0.30),
        side: const BorderSide(color: AppColors.glassMedium, width: 1),
        labelStyle:
            AppTypography.caption1.copyWith(color: AppColors.textOnGlass),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
        ),
      ),
    );
  }

  // ===== Helpers ===============================================

  static RoundedRectangleBorder get _roundedShape =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      );

  /// Filled-style button used by both `ElevatedButton` and
  /// `FilledButton` theme slots. Stealth's primary action shape:
  /// systemBlue fill, mono-friendly height (`AppSpacing.buttonHeight`
  /// = 44 px), rounded `radiusLg` corners.
  static ButtonStyle _filledStyle() => FilledButton.styleFrom(
        backgroundColor: AppColors.systemBlue,
        foregroundColor: AppColors.textOnGlass,
        disabledBackgroundColor: AppColors.systemBlue.withValues(alpha: 0.32),
        disabledForegroundColor:
            AppColors.textOnGlass.withValues(alpha: 0.55),
        elevation: 0,
        minimumSize: const Size(0, AppSpacing.buttonHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        shape: _roundedShape,
        textStyle: AppTypography.bodyEmphasis,
      );
}
