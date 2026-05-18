import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';

/// Branded loading indicator.
///
/// Replaces bare `CircularProgressIndicator()` calls. Uses
/// [AppColors.systemBlue] (the signature accent) and a sizing that
/// looks intentional rather than "default Material".
class StealthLoadingIndicator extends StatelessWidget {
  const StealthLoadingIndicator({
    super.key,
    this.size = 28,
    this.strokeWidth = 2.5,
  });

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.systemBlue),
      ),
    );
  }
}

/// Fullscreen loading overlay — vertically-centred indicator with
/// an optional `label` underneath. Use for screen-level loading
/// states where the whole screen is unusable until the data arrives.
class StealthLoadingOverlay extends StatelessWidget {
  const StealthLoadingOverlay({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StealthLoadingIndicator(size: 32),
          if (label != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              label!,
              style: AppTypography.caption1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
