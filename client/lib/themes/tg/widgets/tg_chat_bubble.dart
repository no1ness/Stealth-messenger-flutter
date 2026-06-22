import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

enum TgMessageType { sent, received }

class TgChatBubble extends StatelessWidget {
  final String message;
  final TgMessageType type;
  final String? timestamp;
  final bool? isRead;
  final bool? isDelivered;
  final Widget? attachmentWidget;
  final Widget? replyPreview;

  const TgChatBubble({
    super.key,
    required this.message,
    required this.type,
    this.timestamp,
    this.isRead,
    this.isDelivered,
    this.attachmentWidget,
    this.replyPreview,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    final isSent = type == TgMessageType.sent;

    final bubbleColor = isSent ? c.backgroundOwn : c.background;
    final textColor = c.text;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(15),
      topRight: const Radius.circular(15),
      bottomLeft: Radius.circular(isSent ? 15 : 4),
      bottomRight: Radius.circular(isSent ? 4 : 15),
    );

    Widget bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: TgSpacing.md, vertical: TgSpacing.sm),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: c.defaultShadow,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyPreview != null) ...[
            replyPreview!,
            const SizedBox(height: TgSpacing.xs),
          ],
          if (attachmentWidget != null) ...[
            attachmentWidget!,
            if (message.isNotEmpty) ...[
              const SizedBox(height: TgSpacing.xs),
              Text(message, style: TextStyle(fontSize: 16, color: textColor, height: 1.4)),
            ],
          ],
          if (attachmentWidget == null)
            Text(message, style: TextStyle(fontSize: 16, color: textColor, height: 1.4)),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: isSent ? TgSpacing.huge : TgSpacing.md,
        right: isSent ? TgSpacing.md : TgSpacing.huge,
        bottom: TgSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          bubble,
          if (timestamp != null || isRead != null || isDelivered != null) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (timestamp != null)
                  Text(timestamp!, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.2)),
                if (isSent && (isRead != null || isDelivered != null)) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead == true ? Icons.done_all : (isDelivered == true ? Icons.done : Icons.access_time),
                    size: 12,
                    color: isRead == true ? c.primary : c.textSecondary,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
