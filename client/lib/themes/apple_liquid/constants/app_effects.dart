/// Tunable parameters for the Stealth signature visual effects.
///
/// These constants control how loud the scan-line / grain / chromatic
/// aberration overlays are. They live in one place so a designer can
/// pull "less" or "more" without grepping the codebase. The defaults
/// are intentionally subtle — the overlays are meant to be felt, not
/// noticed.
///
/// All values are picked for [Brightness.dark]. The overlays
/// auto-disable in [Brightness.light] (see
/// `client/lib/themes/apple_liquid/effects/scanline_overlay.dart`
/// and friends), so light-mode users never see them at any opacity.
class AppEffects {
  AppEffects._();

  // ---- Grain ---------------------------------------------------

  /// Per-pixel opacity for the procedural noise texture in
  /// `GrainOverlay`. 0.04 = "you'd swear the screen is slightly
  /// dusty" — felt but not noticed.
  static const double grainOpacity = 0.04;

  /// Cell size for the procedural noise. Smaller = finer dust;
  /// larger = coarser texture. 1.5 strikes a balance: visible at
  /// 1× and 2×, doesn't shimmer at 3×.
  static const double grainCellPx = 1.5;

  // ---- Scan-line ----------------------------------------------

  /// Alpha multiplier on each scan-line stripe. Multiplied by the
  /// `ScanlineOverlay.intensity` parameter at the call site.
  static const double scanlineOpacity = 0.06;

  /// Vertical pitch between scan-line stripes (pixels). 4 px reads
  /// as "CRT phosphor" at common display densities. Drop to 2 for
  /// a denser, more aggressive look on hero surfaces.
  static const double scanlineSpacingPx = 4.0;

  /// Stripe thickness (pixels). 1 px is the standard "one phosphor
  /// row" feel.
  static const double scanlineThicknessPx = 1.0;

  // ---- Chromatic aberration ----------------------------------

  /// Horizontal offset between the R and B channels of a stack
  /// when chromatic aberration is applied (pixels). 1.5 px reads as
  /// "barely off" at common densities — purely a focus cue.
  static const double aberrationDxPx = 1.5;
}
