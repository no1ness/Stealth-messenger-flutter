import 'package:flutter/material.dart';

import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_elevation.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/effects/scanline_overlay.dart';
import 'package:stealth/themes/apple_liquid/widgets/status_chip.dart';

/// Shared HUD overlay for the WebRTC call screens.
///
/// Renders identically in `webrtc_call_screen_native_impl.dart` and
/// `webrtc_call_screen_web.dart` so the in-call experience is the
/// same across platforms. Three pieces:
///
/// - **Monospace duration timer** — `AppTypography.titleMono` reads
///   like a value out of `date`, not "ui copy".
/// - **Signature "E2E ENCRYPTED" badge** — pulsing blue glow + a
///   subtle scan-line overlay. The single most identifying moment in
///   the app.
/// - **Connection-quality `StatusChip`** — colour-coded chip
///   reflecting "EXCELLENT / GOOD / DEGRADED / RECONNECTING".
class CallHudOverlay extends StatelessWidget {
  const CallHudOverlay({
    super.key,
    required this.duration,
    required this.connectionLabel,
    required this.connectionKind,
  });

  /// Formatted duration ("00:42", "01:13:08"). The widget doesn't
  /// format — callers control granularity.
  final String duration;

  /// Short label for the connection chip ("GOOD", "RECONNECTING").
  final String connectionLabel;
  final StatusKind connectionKind;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Duration timer — mono, prominent.
            Semantics(
              label: AccessibilityIds.callDurationTimer,
              child: Text(
                duration,
                style: AppTypography.titleMono.copyWith(
                  color: AppColors.textOnGlass,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // E2E ENCRYPTED badge — signature element.
            Semantics(
              label: AccessibilityIds.callEncryptedBadge,
              child: ScanlineOverlay(
                intensity: 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.systemBlue.withValues(alpha: 0.16),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusRound),
                    border: Border.all(
                      color: AppColors.systemBlue,
                      width: 1,
                    ),
                    boxShadow: AppElevation.level4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: AppColors.systemBlue,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        'E2E ENCRYPTED',
                        style:
                            AppTypography.caption1Emphasis.copyWith(
                          color: AppColors.systemBlue,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Connection-quality readout.
            Semantics(
              label: AccessibilityIds.callConnectionStatus,
              child: StatusChip(
                label: connectionLabel,
                kind: connectionKind,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
