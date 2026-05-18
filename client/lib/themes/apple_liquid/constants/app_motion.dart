import 'package:flutter/animation.dart';

/// Motion tokens for the Stealth design system.
///
/// Every animation in the app should reach for one of these durations
/// and one of these curves rather than inlining a literal `Duration(
/// milliseconds: 200)` / `Curves.easeOut`. Centralising the values
/// makes it possible to:
///
/// - tune motion globally (e.g. slow everything down for QA video
///   capture by editing the constants);
/// - reason about the choreography: "snackbars enter on
///   [AppMotion.fast]+[AppMotion.emphasized], the dialog scrim
///   fades on [AppMotion.normal]+[AppMotion.standard]" — a stable
///   vocabulary;
/// - keep the design-system doc honest. If a widget needs a duration
///   that isn't here, either it's a new token we should add, or the
///   widget is reaching for a one-off and we should push back.
class AppMotion {
  AppMotion._();

  // ---- Durations -----------------------------------------------

  /// Quick microinteractions — button press, send-confirmed pulse,
  /// snackbar enter, scale-on-tap. Should feel "instant but smooth".
  static const Duration fast = Duration(milliseconds: 150);

  /// Default for component-level reveals — dialog scrim fade, list
  /// stagger step, theme-toggle highlight, route fade. The "you
  /// chose this on purpose" tempo.
  static const Duration normal = Duration(milliseconds: 250);

  /// Larger transitions where settling matters — modal slide-up,
  /// crossfade between two backgrounds, shimmer cycles.
  static const Duration slow = Duration(milliseconds: 400);

  /// Page-route enter/exit. Slightly longer than [normal] to give
  /// the user a moment to register the route change without feeling
  /// laggy.
  static const Duration pageRoute = Duration(milliseconds: 320);

  // ---- Curves --------------------------------------------------

  /// Stealth's signature easing — fast start, lingering finish.
  /// Used for choreographed reveals (route push, staggered list,
  /// hero entrances).
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Balanced ease for everyday transitions (button states, hover
  /// scales, dialog scrim).
  static const Curve standard = Curves.easeInOut;

  /// Asymmetric: slows on the way in, eases on the way out. Use
  /// for dismissals where the user expects the element to "fade
  /// away" rather than snap.
  static const Curve decelerated = Curves.fastOutSlowIn;
}
