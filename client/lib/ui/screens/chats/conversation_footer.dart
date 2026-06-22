import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class ConversationFooter extends StatelessWidget {
  const ConversationFooter({
    super.key,
    required this.replyToMessageText,
    required this.isEditingMessage,
    required this.messagesCount,
    required this.isOtherTyping,
    required this.onCancelReplyOrEdit,
    required this.onSendMessage,
    required this.onAttachment,
    required this.onVoiceRecorded,
    required this.onTypingChanged,
  });

  final String? replyToMessageText;
  final bool isEditingMessage;
  final int messagesCount;
  final bool isOtherTyping;
  final VoidCallback onCancelReplyOrEdit;
  final Future<void> Function(String text) onSendMessage;
  final Future<void> Function() onAttachment;
  final Future<void> Function(String path) onVoiceRecorded;
  final Future<void> Function(bool isTyping) onTypingChanged;

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyToMessageText != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: c.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${isEditingMessage ? 'Редактирование' : 'Ответ на'}: $replyToMessageText',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: onCancelReplyOrEdit,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: messagesCount == 0
                          ? 0.12
                          : messagesCount.clamp(1, 50) / 50,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                      color: c.primary,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$messagesCount сообщ.',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              if (isOtherTyping) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Печатает...',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: c.green,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
        TgMessageInput(
          onSendMessage: onSendMessage,
          onAttachment: onAttachment,
          onVoiceRecorded: onVoiceRecorded,
          onTyping: onTypingChanged,
        ),
      ],
    );
  }
}
