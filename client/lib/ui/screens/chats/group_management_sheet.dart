import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';


/// Opens the "Manage group" bottom sheet for a group chat.
///
/// Extracted from `chats_screen.dart` so the screen widget no longer has
/// to embed ~230 lines of modal UI inline. Callers pass the LocalAppService
/// they already hold, the current self user id, and a callback fired after
/// every membership-changing action (so the surrounding chats screen can
/// reload chats / messages as needed).
Future<void> showManageGroupSheet({
  required BuildContext context,
  required Map<String, dynamic> chat,
  required LocalAppService appService,
  required String? myUserId,
  required Future<void> Function() onMembersChanged,
}) async {
  final chatId = chat['id'] as String;
  final contacts =
      (await appService.getContacts()).cast<Map<String, dynamic>>();
  final members = await appService.getChatMembers(chatId);
  final myRole = await appService.getMyRoleInChat(chatId);
  final isAdmin = myRole == 'admin';
  final memberIds =
      members.map<String>((member) => member['user_id'] as String).toSet();
  final availableContacts = contacts
      .where((contact) => !memberIds.contains(contact['user_id'] as String))
      .toList();
  if (!context.mounted) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setModalState) {
          Future<void> refreshMembers() async {
            final updatedMembers = await appService.getChatMembers(chatId);
            final updatedIds = updatedMembers
                .map<String>((member) => member['user_id'] as String)
                .toSet();
            setModalState(() {
              members
                ..clear()
                ..addAll(updatedMembers);
              availableContacts
                ..clear()
                ..addAll(
                  contacts.where(
                    (contact) =>
                        !updatedIds.contains(contact['user_id'] as String),
                  ),
                );
            });
            await onMembersChanged();
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Управление группой',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    isAdmin
                        ? 'Вы администратор. Вы можете управлять участниками и ролями.'
                        : 'Вы участник. Вы можете просматривать, но не изменять участников.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Участники',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final userId = member['user_id'] as String;
                      final role = member['role'] as String? ?? 'member';
                      final canRemove = isAdmin && userId != myUserId;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(_initials(member['name'] as String?)),
                        ),
                        title: Text(member['name'] as String? ?? 'Неизвестно'),
                        subtitle: Text(
                          '$userId • $role',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        titleTextStyle:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: role == 'admin'
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                        trailing: canRemove
                            ? PopupMenuButton<String>(
                                onSelected: (action) async {
                                  try {
                                    if (action == 'remove') {
                                      await appService
                                          .removeMemberFromGroupChat(
                                        chatId: chatId,
                                        userId: userId,
                                      );
                                    } else if (action == 'promote') {
                                      await appService
                                          .updateGroupMemberRole(
                                        chatId: chatId,
                                        userId: userId,
                                        role: 'admin',
                                      );
                                    } else if (action == 'demote') {
                                      await appService
                                          .updateGroupMemberRole(
                                        chatId: chatId,
                                        userId: userId,
                                        role: 'member',
                                      );
                                    }
                                    await refreshMembers();
                                  } catch (error) {
                                    if (!context.mounted) {
                                      return;
                                    }
                                    showStealthSnackBar(
                                      context,
                                      '$error',
                                      kind: SnackKind.danger,
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (role != 'admin')
                                    const PopupMenuItem(
                                      value: 'promote',
                                      child: Text('Назначить админом'),
                                    ),
                                  if (role == 'admin')
                                    const PopupMenuItem(
                                      value: 'demote',
                                      child: Text('Понизить до участника'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Удалить из группы'),
                                  ),
                                ],
                              )
                            : Icon(
                                role == 'admin'
                                    ? Icons.shield_outlined
                                    : Icons.person_outline,
                              ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Добавить контакты',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                SizedBox(
                  height: 220,
                  child: availableContacts.isEmpty
                      ? const Center(child: Text('Нет контактов для добавления'))
                      : !isAdmin
                          ? const Center(
                              child: Text('Только админы могут добавлять участников'),
                            )
                          : ListView.builder(
                              itemCount: availableContacts.length,
                              itemBuilder: (context, index) {
                                final contact = availableContacts[index];
                                final userId = contact['user_id'] as String;
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      _initials(contact['name'] as String?),
                                    ),
                                  ),
                                  title: Text(
                                      contact['name'] as String? ?? 'Неизвестно'),
                                  subtitle: Text(
                                    userId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: FilledButton(
                                    onPressed: () async {
                                      try {
                                        await appService
                                            .addMembersToGroupChat(
                                          chatId: chatId,
                                          memberIds: [userId],
                                        );
                                        await refreshMembers();
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        showStealthSnackBar(
                                          context,
                                          '$error',
                                          kind: SnackKind.danger,
                                        );
                                      }
                                    },
                                    child: const Text('Добавить'),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _initials(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '?';
  }

  final parts = value.trim().split(RegExp(r'\s+'));
  final first = parts.first.isNotEmpty ? parts.first[0] : '';
  final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
  return (first + last).toUpperCase();
}
