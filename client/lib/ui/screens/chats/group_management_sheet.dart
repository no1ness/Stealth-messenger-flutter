import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stealth/di.dart';

/// Opens the "Manage group" bottom sheet for a group chat.
///
/// Extracted from `chats_screen.dart` so the screen widget no longer has
/// to embed ~230 lines of modal UI inline. Callers pass the
/// `WidgetRef` they already hold, the current self user id, and a
/// callback fired after every membership-changing action (so the
/// surrounding chats screen can reload chats / messages as needed).
Future<void> showManageGroupSheet({
  required BuildContext context,
  required Map<String, dynamic> chat,
  required WidgetRef ref,
  required String? myUserId,
  required Future<void> Function() onMembersChanged,
}) async {
  final appService = ref.read(localAppServiceProvider);
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
                  'Manage group',
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
                        ? 'You are an admin. You can manage members and roles.'
                        : 'You are a member. You can view participants but not change them.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Members',
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
                        title: Text(member['name'] as String? ?? 'Unknown'),
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
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(content: Text('$error')),
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (role != 'admin')
                                    const PopupMenuItem(
                                      value: 'promote',
                                      child: Text('Promote to admin'),
                                    ),
                                  if (role == 'admin')
                                    const PopupMenuItem(
                                      value: 'demote',
                                      child: Text('Demote to member'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Remove from group'),
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
                  'Add contacts',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                SizedBox(
                  height: 220,
                  child: availableContacts.isEmpty
                      ? const Center(child: Text('No more contacts to add'))
                      : !isAdmin
                          ? const Center(
                              child: Text('Only admins can add members'),
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
                                      contact['name'] as String? ?? 'Unknown'),
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
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(content: Text('$error')),
                                        );
                                      }
                                    },
                                    child: const Text('Add'),
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
