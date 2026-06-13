import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Elevation / depth tokens for the Stealth design system.
///
/// We don't ship traditional Material elevation values
/// (`elevation: 4.0`). Glass surfaces use multi-layer `BoxShadow`
/// stacks to convey depth + the signature blue glow. These presets
/// keep the stack consistent across `GlassContainer`, `StealthDialog`,
/// `StealthSnackBar`, and any future surface widget.
///
/// Levels:
///
/// - **level0** — flat (no shadow). Inline labels, captions,
///   strings drawn directly on the background.
/// - **level1** — barely lifted. List rows, subtle separations.
/// - **level2** — standard card lift. The default for
///   `GlassContainer(intensity: light)` and most settings cells.
/// - **level3** — pronounced lift. Dialogs, popovers, peek-style
///   modal sheets.
/// - **level4** — dramatic lift. Hero cards (the profile
///   `IdentityCard`), in-call HUD overlays. Adds the signature
///   systemBlue glow.
class AppElevation {
  AppElevation._();

  static const List<BoxShadow> level0 = <BoxShadow>[];

  static const List<BoxShadow> level1 = <BoxShadow>[
    BoxShadow(
      color: AppColors.shadow,
      blurRadius: 8,
      spreadRadius: 0,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> level2 = <BoxShadow>[
    BoxShadow(
      color: AppColors.shadow,
      blurRadius: 16,
      spreadRadius: 0,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> level3 = <BoxShadow>[
    BoxShadow(
      color: AppColors.shadowStrong,
      blurRadius: 24,
      spreadRadius: 0,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: AppColors.shadow,
      blurRadius: 6,
      spreadRadius: 0,
      offset: Offset(0, 2),
    ),
  ];

  /// Hero level — drop shadow plus the signature [AppColors.systemBlue]
  /// glow. Used sparingly: the profile `IdentityCard`, the in-call
  /// "E2E ENCRYPTED" badge, the `DialogImportance.high` body.
  static const List<BoxShadow> level4 = <BoxShadow>[
    BoxShadow(
      color: AppColors.shadowStrong,
      blurRadius: 32,
      spreadRadius: 0,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      // 0x26 = ~15% alpha — visible halo at typical card sizes
      // without becoming a fog at small sizes.
      color: Color(0x26007AFF),
      blurRadius: 40,
      spreadRadius: 0,
      offset: Offset(0, 0),
    ),
  ];
}
