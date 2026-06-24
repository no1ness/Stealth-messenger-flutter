import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

class TgChatTile extends StatelessWidget {
  final Map<String, dynamic> chat;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool? isSent;
  final bool? isRead;
  final bool? isDelivered;
  final bool isVerified;
  final bool isPinned;

  const TgChatTile({
    super.key,
    required this.chat,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.isSent,
    this.isRead,
    this.isDelivered,
    this.isVerified = false,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    final name = chat['name'] as String? ?? '';
    final unreadCount = chat['unreadCount'] as int? ?? 0;
    final lastMessage = chat['lastMessage'] as String?;
    final timestamp = chat['timestamp'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: TgSpacing.screenEdge, vertical: TgSpacing.xxs),
      decoration: BoxDecoration(
        color: isSelected ? c.primaryOpacityHover : Colors.transparent,
        borderRadius: BorderRadius.circular(TgSpacing.radiusXl),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgSpacing.radiusXl)),
        onTap: onTap,
        onLongPress: onLongPress,
        leading: Stack(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: _avatarGradient(name),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(name),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            if (isVerified)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blue),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        title: Text(
          name,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text, height: 1.4),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (lastMessage != null && lastMessage.isNotEmpty)
              Text(
                '✓ ',
                style: TextStyle(fontSize: 14, color: c.green, height: 1.35),
              ),
            Expanded(
              child: Text(
                lastMessage ?? '',
                style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.35),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: SizedBox(
          width: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(timestamp, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.2)),
              if (unreadCount > 0) ...[
                const SizedBox(height: TgSpacing.xxs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: TgSpacing.xs, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(TgSpacing.radiusRound),
                  ),
                  child: Text('$unreadCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
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

  static String _initials(String value) {
    if (value.trim().isEmpty) return '?';
    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
