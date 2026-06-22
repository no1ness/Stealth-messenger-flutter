import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:stealth/ui/screens/chats_screen.dart';

Future<void> showUserDetailSheet(
    BuildContext context, Map<String, dynamic> contact) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _UserDetailSheet(contact: contact),
  );
}

class _UserDetailSheet extends StatelessWidget {
  const _UserDetailSheet({required this.contact});

  final Map<String, dynamic> contact;

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);

    final name = contact['name'] as String? ?? 'Неизвестно';
    final userId = (contact['user_id'] ?? contact['contact_user_id'] ?? '').toString();
    final deviceModel = contact['deviceModel'] as String?;
    final platform = contact['platform'] as String?;
    final appVersion = contact['appVersion'] as String?;
    final registeredAt = contact['registeredAt'] as String?;
    final lastSeen = contact['lastSeen'] as String?;
    final isOnline = contact['isOnline'] as bool?;
    final autoPopulated = contact['auto_populated'] as bool? ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TgSpacing.md),
          child: ListView(
            controller: scrollController,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: c.primary,
                child: Text(
                  _initials(name),
                  style: TgTypography.title1.copyWith(
                    color: c.text,
                  ),
                ),
              ),
              const SizedBox(height: TgSpacing.md),
              Text(
                name,
                textAlign: TextAlign.center,
                style: TgTypography.title2.copyWith(
                  color: c.text,
                ),
              ),
              const SizedBox(height: TgSpacing.xs),
              Text(
                userId,
                textAlign: TextAlign.center,
                style: TgTypography.captionMono.copyWith(
                  color: c.textSecondary,
                ),
              ),
              if (isOnline != null) ...[
                const SizedBox(height: TgSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? c.green
                            : c.gray,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: TgSpacing.xs),
                    Text(
                      isOnline ? 'В сети' : 'Не в сети',
                      style: TgTypography.caption1.copyWith(
                        color:
                            isOnline ? c.green : c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: TgSpacing.lg),
              if (deviceModel != null || platform != null) ...[
                _sectionHeader('Устройство'),
                if (deviceModel != null) _infoRow('Модель', deviceModel),
                if (platform != null) _infoRow('Платформа', platform),
              ],
              if (appVersion != null) ...[
                _sectionHeader('Приложение'),
                _infoRow('Версия', appVersion),
              ],
              if (registeredAt != null || lastSeen != null || isOnline != null) ...[
                _sectionHeader('Активность'),
                if (registeredAt != null)
                  _infoRow('Зарегистрирован', _formatDate(registeredAt)),
                if (lastSeen != null)
                  _infoRow('Последний раз', _formatDate(lastSeen)),
                if (isOnline != null)
                  _infoRow('Статус', isOnline ? 'Online' : 'Offline'),
              ],
              const SizedBox(height: TgSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Написать сообщение',
                      button: true,
                      child: FilledButton.icon(
                        onPressed: () {
                          TgHaptics.light(context);
                          Navigator.of(context).pop();
                          _openChat(context, userId);
                        },
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Написать сообщение'),
                      ),
                    ),
                  ),
                  const SizedBox(width: TgSpacing.sm),
                  Expanded(
                    child: Semantics(
                      label: 'Позвонить',
                      button: true,
                      child: FilledButton.icon(
                        onPressed: () {
                          TgHaptics.light(context);
                          Navigator.of(context).pop();
                          _startCall(context, contact);
                        },
                        icon: const Icon(Icons.call),
                        label: const Text('Позвонить'),
                      ),
                    ),
                  ),
                ],
              ),
              if (!autoPopulated) ...[
                const SizedBox(height: TgSpacing.sm),
                Semantics(
                  label: 'Редактировать профиль',
                  button: true,
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Редактировать профиль'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: TgSpacing.md, bottom: TgSpacing.xs),
      child: Text(
        title,
        style: TgTypography.caption1.copyWith(
          color: c.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TgSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TgTypography.body.copyWith(color: c.textSecondary)),
          Text(value, style: TgTypography.body.copyWith(color: c.text)),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, String userId) {
    LocalAppService().findOrCreatePrivateChatWith(userId).then((chatId) {
      if (chatId == null || !context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatsScreen(initialChatId: chatId),
        ),
      );
    });
  }

  void _startCall(BuildContext context, Map<String, dynamic> contact) {
    // Simplified: navigate to WebRTCCallScreen.
    final chatIdFuture = LocalAppService().findOrCreatePrivateChatWith(
      (contact['user_id'] ?? contact['contact_user_id'] ?? '').toString(),
    );
    chatIdFuture.then((chatId) {
      if (chatId == null || !context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatsScreen(initialChatId: chatId),
        ),
      );
    });
  }

  String _initials(String value) {
    if (value.trim().isEmpty) return '?';
    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
          ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
