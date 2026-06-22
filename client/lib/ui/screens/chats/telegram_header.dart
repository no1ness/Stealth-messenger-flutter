import 'package:flutter/material.dart';
import 'package:stealth/themes/apple_liquid/theme_exports.dart';
import 'package:stealth/p2p_service.dart';

/// Telegram-style chat header with avatar, name, and status.
///
/// Shows when a chat is selected on desktop, or as app bar on mobile.
class TelegramHeader extends StatelessWidget {
  const TelegramHeader({
    super.key,
    required this.chatName,
    required this.chatId,
    this.onBack,
    this.onMenuPressed,
  });

  final String chatName;
  final String chatId;
  final VoidCallback? onBack;
  final VoidCallback? onMenuPressed;

  @override
  Widget build(BuildContext context) {
    final isP2P = P2PService.instance.isP2PReady(chatId);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.dividerSubtle,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 20),
              onPressed: onBack,
              color: AppColors.systemBlue,
            ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: _avatarGradient(chatName),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(chatName),
              style: AppTypography.calloutEmphasis.copyWith(
                color: AppColors.textOnGlass,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chatName,
                  style: AppTypography.bodyEmphasis.copyWith(
                    color: AppColors.textOnGlass,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isP2P
                            ? AppColors.systemGreen
                            : AppColors.systemBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isP2P ? 'P2P' : 'Локально',
                      style: AppTypography.caption1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onMenuPressed != null)
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              onPressed: onMenuPressed,
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }

  static Gradient _avatarGradient(String name) {
    final hash = name.hashCode;
    final hue1 = (hash.abs() % 360).toDouble();
    final hue2 = ((hash.abs() * 7 + 120) % 360).toDouble();
    return LinearGradient(
      colors: [
        HSLColor.fromAHSL(1, hue1, 0.7, 0.4).toColor(),
        HSLColor.fromAHSL(1, hue2, 0.7, 0.3).toColor(),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  static String _initials(String? value) {
    if (value == null || value.trim().isEmpty) return '?';
    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
