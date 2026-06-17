import 'package:flutter/material.dart';

import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_motion.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';

/// One row in the chats list.
///
/// Extracted from `chats_screen.dart` to keep the screen's
/// `build` method readable and to centralise the visual contract.
/// Reads only from the `chat` map; the screen owns selection state
/// and callbacks.
///
/// Preserves the existing Semantics contract: each tile is labelled
/// `AccessibilityIds.chat(name)` and exposed as a button — required
/// by the Appium suite.
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  final Map<String, dynamic> chat;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final name = chat['name'] as String? ?? 'Чат';
    final unreadCount = chat['unreadCount'] as int? ?? 0;
    final memberCount = chat['memberCount'] as int? ?? 0;
    final isPrivate = chat['isPrivate'] as bool? ?? true;
    final lastMessage = chat['lastMessage'] as String?;
    final timestamp = chat['timestamp'] as String? ?? '';

    return Semantics(
      label: AccessibilityIds.chat(name),
      button: true,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenEdge,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.systemBlue.withValues(alpha: 0.16)
              : AppColors.glassMedium.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(
            color: isSelected
                ? AppColors.systemBlue.withValues(alpha: 0.45)
                : AppColors.glassMedium.withValues(alpha: 0.30),
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          onTap: onTap,
          onLongPress: onLongPress,
          leading: Semantics(
            label: AccessibilityIds.chatTileAvatar,
            child: CircleAvatar(
              backgroundColor: AppColors.systemBlue.withValues(alpha: 0.85),
              child: Text(
                _initials(name),
                style: AppTypography.calloutEmphasis.copyWith(
                  color: AppColors.textOnGlass,
                ),
              ),
            ),
          ),
          title: Text(
            name,
            style: AppTypography.bodyEmphasis.copyWith(
              color: AppColors.textOnGlass,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Semantics(
            label: AccessibilityIds.chatTileLastMessage,
            child: Text(
              (lastMessage == null || lastMessage.isEmpty)
                  ? (isPrivate ? 'Нет сообщений' : '$memberCount участников')
                  : lastMessage,
              style: AppTypography.subheadline.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: SizedBox(
            width: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timestamp,
                  style: AppTypography.captionMono.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Semantics(
                    label: AccessibilityIds.chatTileUnreadBadge,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.systemBlue,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusRound,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.systemBlue.withValues(alpha: 0.15),
                            blurRadius: 3,
                            spreadRadius: 0,
                            offset: Offset.zero,
                          ),
                        ],
                      ),
                      child: Text(
                        '$unreadCount',
                        style: AppTypography.caption2Emphasis.copyWith(
                          color: AppColors.textOnGlass,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
