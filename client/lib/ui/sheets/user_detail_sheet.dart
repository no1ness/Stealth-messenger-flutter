import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/theme_exports.dart';
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ListView(
            controller: scrollController,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.systemBlue,
                child: Text(
                  _initials(name),
                  style: AppTypography.title1.copyWith(
                    color: AppColors.textOnGlass,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                name,
                textAlign: TextAlign.center,
                style: AppTypography.title2.copyWith(
                  color: AppColors.textOnGlass,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                userId,
                textAlign: TextAlign.center,
                style: AppTypography.captionMono.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (isOnline != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? AppColors.systemGreen
                            : AppColors.systemGray,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      isOnline ? 'В сети' : 'Не в сети',
                      style: AppTypography.caption1.copyWith(
                        color:
                            isOnline ? AppColors.systemGreen : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Написать сообщение',
                      button: true,
                      child: FilledButton.icon(
                        onPressed: () {
                          StealthHaptics.light(context);
                          Navigator.of(context).pop();
                          _openChat(context, userId);
                        },
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Написать сообщение'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Semantics(
                      label: 'Позвонить',
                      button: true,
                      child: FilledButton.icon(
                        onPressed: () {
                          StealthHaptics.light(context);
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
                const SizedBox(height: AppSpacing.sm),
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
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(
        title,
        style: AppTypography.caption1.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          Text(value, style: AppTypography.body.copyWith(color: AppColors.textOnGlass)),
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
