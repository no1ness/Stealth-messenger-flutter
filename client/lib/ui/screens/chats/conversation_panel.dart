import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_chat_bubble.dart'
    as glass;
import 'package:stealth/ui/screens/chats/conversation_attachment.dart';
import 'package:stealth/ui/widgets/empty_state.dart';

class ConversationPanel extends StatelessWidget {
  const ConversationPanel({
    super.key,
    required this.loadingMessages,
    required this.loadingOlderMessages,
    required this.hasMoreMessages,
    required this.pinnedMessage,
    required this.messageSearchController,
    required this.searchInConversation,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.scrollController,
    required this.messages,
    required this.visibleMessages,
    required this.onLoadOlder,
    required this.onMessageLongPress,
    required this.appService,
    required this.chatId,
    required this.footer,
  });

  final bool loadingMessages;
  final bool loadingOlderMessages;
  final bool hasMoreMessages;
  final Map<String, dynamic>? pinnedMessage;
  final TextEditingController messageSearchController;
  final bool searchInConversation;
  final VoidCallback onSearchChanged;
  final VoidCallback onSearchCleared;
  final ScrollController scrollController;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> visibleMessages;
  final Future<void> Function() onLoadOlder;
  final void Function(Map<String, dynamic> message) onMessageLongPress;
  final LocalAppService appService;
  final String chatId;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    if (loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (pinnedMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.systemYellow.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.systemYellow.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pinnedMessage?['content'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageSearchController,
                  onChanged: (_) => onSearchChanged(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search in conversation',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (searchInConversation) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onSearchCleared,
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: visibleMessages.isEmpty
              ? const EmptyState(type: 'chats')
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  itemCount: visibleMessages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      if (loadingOlderMessages) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (hasMoreMessages) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: OutlinedButton(
                              onPressed: onLoadOlder,
                              child: const Text('Load older messages'),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    final message = visibleMessages[index - 1];
                    final replyToId = message['reply_to_id'] as String?;
                    final repliedMessage = replyToId == null
                        ? null
                        : messages.cast<Map<String, dynamic>?>().firstWhere(
                              (candidate) =>
                                  candidate?['id'].toString() == replyToId,
                              orElse: () => null,
                            );

                    return GestureDetector(
                      onLongPress: () => onMessageLongPress(message),
                      child: glass.GlassChatBubble(
                        message:
                            '${message['message'] as String? ?? ''}${message['edited_at'] != null ? ' (edited)' : ''}',
                        timestamp: message['timestamp'] as String?,
                        isDelivered: message['isDelivered'] as bool?,
                        isRead: message['isRead'] as bool?,
                        attachmentWidget: buildConversationAttachment(
                          message: message,
                          appService: appService,
                          chatId: chatId,
                        ),
                        replyPreview: repliedMessage == null
                            ? null
                            : _ReplyPreview(
                                text:
                                    repliedMessage['message'] as String? ?? '',
                              ),
                        type: (message['isSent'] as bool? ?? false)
                            ? glass.MessageType.sent
                            : glass.MessageType.received,
                      ),
                    );
                  },
                ),
        ),
        footer,
      ],
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
