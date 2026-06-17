import 'package:flutter/material.dart';

import '../../../logging/logger.dart';
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
/// When [count] is provided a numeric badge is rendered right-aligned
/// on the same row as the title, preceding any [trailing] widget.
///
/// Wrapped in `Semantics(header: true)` so screen readers announce
/// section boundaries — important for navigation between groups.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding,
    this.count,
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final int? count;

  @override
  Widget build(BuildContext context) {
    Logger.debug('[ds:section-header] title=$title count=$count');
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
          Semantics(
            header: true,
            label: title,
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontFamily: AppTypography.fontFamilyMono,
                fontFamilyFallback: AppFontStacks.monoFallbacks,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
                height: 1,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.systemBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x30007AFF),
                    blurRadius: 4,
                    spreadRadius: 0,
                    offset: Offset(0, 0),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamilyMono,
                    fontFamilyFallback: AppFontStacks.monoFallbacks,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.systemBlue.withValues(alpha: 0.9),
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
