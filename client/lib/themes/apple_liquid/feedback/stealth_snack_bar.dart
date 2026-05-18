import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import 'stealth_haptics.dart';

/// Semantic kinds for [showStealthSnackBar]. The kind drives the
/// accent-stripe color, the auto-haptic, and (on long-form snacks)
/// the icon.
enum SnackKind { info, success, warn, danger }

/// Show a Stealth-branded snackbar.
///
/// Replaces every bare `ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(...))`
/// call in the app. Provides:
///
/// - **Consistent visual treatment** — glass surface, sharp accent
///   stripe on the leading edge, [AppTypography.body] text, soft
///   shadow from `AppElevation`.
/// - **Auto-haptic** — info → no haptic, success → success,
///   warn → warn, danger → error.
/// - **Above the bottom nav** — `behavior: SnackBarBehavior.floating`
///   with bottom margin of [AppSpacing.bottomBarOverlap] + a small
///   gap, so the snackbar doesn't overlap `GlassBottomNavBar`.
/// - **Reduce-motion respect** — when `MediaQuery.disableAnimations`
///   is true the snackbar still appears but the haptic is silenced
///   (via [StealthHaptics]). The slide-in animation comes from the
///   framework and is also reduced when the system flag is set.
void showStealthSnackBar(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.info,
  Duration? duration,
  SnackBarAction? action,
}) {
  final accent = _accentFor(kind);
  final haptic = _hapticFor(kind);

  debugPrint('[ds:snack] kind=$kind msg=$message');

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    // Defensive: caller passed a context outside a Scaffold. Log
    // and bail rather than throw — a missing snackbar is recoverable.
    debugPrint('[ds:snack] no ScaffoldMessenger in context — dropping');
    return;
  }

  if (haptic != null) {
    StealthHaptics.fire(context, haptic);
  }

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.bottomBarOverlap,
      ),
      padding: EdgeInsets.zero,
      duration: duration ?? const Duration(seconds: 4),
      content: _StealthSnackBody(
        message: message,
        accent: accent,
        action: action,
      ),
    ),
  );
}

/// Internal: the actual glass-card body of the snackbar.
class _StealthSnackBody extends StatelessWidget {
  const _StealthSnackBody({
    required this.message,
    required this.accent,
    this.action,
  });

  final String message;
  final Color accent;
  final SnackBarAction? action;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: AppColors.glassMedium,
            width: 1,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                color: accent,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    message,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textOnGlass,
                    ),
                  ),
                ),
              ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: TextButton(
                    onPressed: action!.onPressed,
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                    ),
                    child: Text(action!.label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _accentFor(SnackKind kind) {
  switch (kind) {
    case SnackKind.info:
      return AppColors.statusInfo;
    case SnackKind.success:
      return AppColors.statusSuccess;
    case SnackKind.warn:
      return AppColors.statusWarn;
    case SnackKind.danger:
      return AppColors.statusDanger;
  }
}

HapticIntensity? _hapticFor(SnackKind kind) {
  switch (kind) {
    case SnackKind.info:
      return null;
    case SnackKind.success:
      return HapticIntensity.success;
    case SnackKind.warn:
      return HapticIntensity.warn;
    case SnackKind.danger:
      return HapticIntensity.error;
  }
}
