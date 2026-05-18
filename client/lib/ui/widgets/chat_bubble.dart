import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_dialog.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_snack_bar.dart';
import 'voice_message_player.dart';

class ChatBubble extends StatelessWidget {
  final String message;
  final String timestamp;
  final bool isSent;
  final bool isDelivered;
  final bool isRead;
  final bool isEncrypted;
  final String? type; // 'text' | 'image' | 'audio' | 'file'
  final String? messageId; // ID сообщения для удаления
  final VoidCallback? onDeleted; // Callback после удаления

  const ChatBubble({
    super.key,
    required this.message,
    required this.timestamp,
    required this.isSent,
    this.isDelivered = false,
    this.isRead = false,
    this.isEncrypted = true,
    this.type,
    this.messageId,
    this.onDeleted,
  });

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http') && (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp') || lower.contains('content_type=image') || lower.contains('/image'));
  }

  bool _isAudioUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http') && (lower.endsWith('.m4a') || lower.endsWith('.aac') || lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.ogg') || lower.endsWith('.opus') || lower.contains('/audio'));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final result = await showStealthDialog<bool>(
      context: context,
      title: 'Удалить сообщение?',
      body: const Text('Это действие нельзя отменить.'),
      importance: DialogImportance.high,
      actions: const [
        StealthDialogAction<bool>(label: 'Отмена', result: false),
        StealthDialogAction<bool>.destructive(label: 'Удалить', result: true),
      ],
    );

    if (result != true || messageId == null) return;
    if (!context.mounted) return;

    try {
      // await LocalAppService().softDeleteMessage(messageId: messageId!);
      onDeleted?.call();
      if (!context.mounted) return;
      showStealthSnackBar(
        context,
        'Сообщение удалено',
        kind: SnackKind.success,
        duration: const Duration(seconds: 1),
      );
    } catch (e) {
      if (!context.mounted) return;
      showStealthSnackBar(context, 'Ошибка: $e', kind: SnackKind.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isSent
        ? (isDarkMode ? Colors.blue.shade700 : Colors.blue.shade600)
        : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300);
    final textColor = isSent
        ? (isDarkMode ? Colors.white : Colors.white)
        : (isDarkMode ? Colors.white : Colors.black87);
    final timestampColor = isSent
        ? (isDarkMode ? Colors.white70 : Colors.blue.shade200)
        : (isDarkMode ? Colors.white70 : Colors.black54);

    final String renderType = type ?? (() {
      if (_isImageUrl(message)) return 'image';
      if (_isAudioUrl(message)) return 'audio';
      if (message.toLowerCase().startsWith('http')) return 'file';
      return 'text';
    })();

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: messageId != null ? () => _showDeleteDialog(context) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isSent ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight: isSent ? const Radius.circular(4) : const Radius.circular(16),
            ),
          ),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (renderType == 'image')
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  message,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Text(
                    'Изображение недоступно',
                    style: TextStyle(color: textColor),
                  ),
                ),
              )
            else if (renderType == 'audio')
              VoiceMessagePlayer(
                audioUrl: message,
                isSent: isSent,
              )
            else if (renderType == 'file') ...[
              Text(
                message,
                style: TextStyle(color: textColor, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _openUrl(message),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Открыть'),
                  style: OutlinedButton.styleFrom(foregroundColor: textColor),
                ),
              ),
            ]
            else
              Text(
                message,
                style: TextStyle(color: textColor, fontSize: 16),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    timestamp,
                    style: TextStyle(color: timestampColor, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isEncrypted) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.lock,
                    size: 12,
                    color: timestampColor,
                  ),
                ],
                if (isSent) ...[
                  const SizedBox(width: 2),
                  Icon(
                    isRead ? Icons.done_all : (isDelivered ? Icons.done_all : Icons.done),
                    size: 14,
                    color: isRead
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.7)
                        : timestampColor,
                  ),
                ],
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
