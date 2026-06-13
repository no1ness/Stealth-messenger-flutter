import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';

/// Section header used at the top of grouped lists (Settings groups,
/// Chats "Pinned"/"Recent", Profile card group titles, etc.).
///
/// Renders the [title] in [AppTypography.title3] on a transparent
/// background, optional [trailing] action on the right (typically a
/// `TextButton` or icon button like "See all" / "+ Add").
///
/// Wrapped in `Semantics(header: true)` so screen readers announce
/// section boundaries — important for navigation between groups.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding,
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    debugPrint('[ds:section-header] title=$title');
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.screenEdge,
            AppSpacing.md,
            AppSpacing.screenEdge,
            AppSpacing.xs,
          ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              label: title,
              child: Text(
                title,
                style: AppTypography.title3.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
