import 'package:flutter/material.dart';

import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';

/// One card in the contacts grid.
///
/// Extracted from `contacts_screen.dart` to keep the screen's render
/// path readable. Preserves the existing Semantics contract — the
/// outer wrapper is labelled `AccessibilityIds.contact(name)` and
/// exposed as a button (the Appium suite depends on this label).
class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final Map<String, dynamic> contact;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final name = contact['name'] as String? ?? 'Unknown';
    final userId = contact['user_id'] as String? ?? '';
    return Semantics(
      label: AccessibilityIds.contact(name),
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        onTap: onTap,
        onLongPress: onLongPress,
        child: GlassContainer(
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.systemBlue,
                child: Text(
                  _initials(name),
                  style: AppTypography.calloutEmphasis.copyWith(
                    color: AppColors.textOnGlass,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyEmphasis.copyWith(
                        color: AppColors.textOnGlass,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      userId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionMono.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Semantics(
                  label: AccessibilityIds.contactTileTrailing,
                  child: trailing!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '?';
    }
    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last =
        parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
