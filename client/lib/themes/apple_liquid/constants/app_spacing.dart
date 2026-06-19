class AppSpacing {
  AppSpacing._();

  // Base spacing unit (4px)
  static const double unit = 4.0;

  // Micro spacing
  static const double xxxs = unit * 0.5; // 2px
  static const double xxs = unit; // 4px
  static const double xs = unit * 2; // 8px

  // Small spacing
  static const double sm = unit * 3; // 12px
  static const double md = unit * 4; // 16px

  // Medium spacing
  static const double lg = unit * 5; // 20px
  static const double xl = unit * 6; // 24px

  // Large spacing
  static const double xxl = unit * 8; // 32px
  static const double xxxl = unit * 10; // 40px

  // Extra large spacing
  static const double huge = unit * 12; // 48px
  static const double massive = unit * 16; // 64px

  // Screen padding (Apple standard)
  static const double screenPadding = 16.0;
  static const double screenPaddingLarge = 20.0;

  // Card and container spacing
  static const double cardPadding = 16.0;
  static const double cardMargin = 12.0;

  // List spacing
  static const double listItemHeight = 44.0; // Apple standard touch target
  static const double listItemPadding = 16.0;
  static const double listSpacing = 8.0;

  // Border Radius (Apple style)
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusXxl = 24.0;
  static const double radiusRound = 999.0; // Fully rounded

  // Glass effect specific. Keep blur radii modest: large backdrop sigmas
  // are one of the easiest ways to drop frames on chat scroll.
  static const double glassBlur = 8.0;
  static const double glassBlurLight = 6.0;

  // Icon sizes
  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 40.0;
  static const double iconXxl = 48.0;

  // Button heights (Apple standard)
  static const double buttonHeightSmall = 32.0;
  static const double buttonHeightMedium = 44.0; // Apple standard
  static const double buttonHeightLarge = 50.0;

  // Navigation bar height
  static const double navBarHeight = 44.0;
  static const double navBarLargeHeight = 96.0;
  static const double tabBarHeight = 56.0; // Increased to prevent overflow

  // Safe area additions
  static const double bottomSafeArea = 34.0; // iPhone bottom notch
  static const double topSafeArea = 44.0; // iPhone top notch

  // --------------------------------------------------------------
  // Semantic aliases — design-system v2. New widgets should prefer
  // these over the raw scale tokens (`md`, `lg`, etc.) so the
  // intent of the spacing travels with the code.
  // --------------------------------------------------------------

  /// Horizontal inset for the contents of any top-level screen.
  /// Matches the iOS standard list inset.
  static const double screenEdge = screenPadding; // 16

  /// Horizontal+vertical gap between rows in a list/grid where the
  /// rows themselves carry their own padding. Smaller than
  /// [cardMargin] so dense lists do not feel airy.
  static const double tileGap = 8.0;

  /// Extra bottom inset that screens with the `GlassBottomNavBar`
  /// must apply so floating content (FABs, snackbars, last list
  /// row) does not sit underneath the nav bar.
  static const double bottomBarOverlap = tabBarHeight + 24.0; // 80

  /// Default button height — the iOS-standard 44 pt touch target.
  /// Alias of [buttonHeightMedium].
  static const double buttonHeight = buttonHeightMedium;
}
