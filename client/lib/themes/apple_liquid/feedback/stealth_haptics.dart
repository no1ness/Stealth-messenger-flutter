import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_haptics.dart';

export '../constants/app_haptics.dart';

/// Centralised haptic feedback service.
///
/// Widgets call e.g. `StealthHaptics.fire(context, HapticIntensity.success)`
/// or the convenience methods (`StealthHaptics.light(context)`, etc.).
/// The service:
///
/// - maps semantic intent → `HapticFeedback.*` calls;
/// - sequences compound patterns (`success` = medium → light,
///   `error` = heavy × 2) with appropriate delays;
/// - no-ops on web (Flutter `HapticFeedback` has no web backend);
/// - respects `MediaQuery.disableAnimations` — haptics are motion,
///   and motion-sensitive users opt out of both at once.
///
/// Keeping all platform routing here means widgets never have to
/// reach for `HapticFeedback.*` directly, and the test harness can
/// inject a fake via mock platform channels if needed.
class StealthHaptics {
  StealthHaptics._();

  // ----- Convenience entry points -------------------------------

  static Future<void> light(BuildContext context) =>
      fire(context, HapticIntensity.light);

  static Future<void> medium(BuildContext context) =>
      fire(context, HapticIntensity.medium);

  static Future<void> heavy(BuildContext context) =>
      fire(context, HapticIntensity.heavy);

  static Future<void> success(BuildContext context) =>
      fire(context, HapticIntensity.success);

  static Future<void> warn(BuildContext context) =>
      fire(context, HapticIntensity.warn);

  static Future<void> error(BuildContext context) =>
      fire(context, HapticIntensity.error);

  static Future<void> selection(BuildContext context) =>
      fire(context, HapticIntensity.selection);

  // ----- Core dispatch ------------------------------------------

  /// Fire a haptic of the given semantic [intensity].
  ///
  /// Silently no-ops when:
  /// - the platform has no haptic backend (web);
  /// - the user has reduce-motion enabled
  ///   (`MediaQuery.disableAnimations == true`).
  static Future<void> fire(
    BuildContext context,
    HapticIntensity intensity,
  ) async {
    if (kIsWeb) {
      // Flutter `HapticFeedback.*` has no web backend; calling it
      // throws `MissingPluginException`. Document the no-op.
      return;
    }
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disable) {
      debugPrint('[haptics] $intensity (suppressed: disableAnimations)');
      return;
    }
    debugPrint('[haptics] $intensity');
    switch (intensity) {
      case HapticIntensity.light:
        await HapticFeedback.lightImpact();
        break;
      case HapticIntensity.medium:
        await HapticFeedback.mediumImpact();
        break;
      case HapticIntensity.heavy:
        await HapticFeedback.heavyImpact();
        break;
      case HapticIntensity.selection:
        await HapticFeedback.selectionClick();
        break;
      case HapticIntensity.success:
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await HapticFeedback.lightImpact();
        break;
      case HapticIntensity.warn:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await HapticFeedback.lightImpact();
        break;
      case HapticIntensity.error:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await HapticFeedback.heavyImpact();
        break;
    }
  }
}
