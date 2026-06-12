import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';

/// Opens the "Create group chat" bottom sheet.
///
/// Extracted from `chats_screen.dart`. The caller owns the
/// [TextEditingController] for the group name so the field is preserved
/// across re-opens (matches the previous inline behaviour where the field
/// belonged to `_groupNameController`).
///
/// [onGroupCreated] is invoked with the new chat id once the group has
/// been created. The chats screen uses it to reload chats and select the
/// freshly created room.
Future<void> showCreateGroupSheet({
  required BuildContext context,
  required LocalAppService appService,
  required TextEditingController nameController,
  required Future<void> Function(String chatId) onGroupCreated,
}) async {
  final contacts =
      (await appService.getContacts()).cast<Map<String, dynamic>>();
  final selectedIds = <String>{};
  nameController.clear();
  if (!context.mounted) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setModalState) {
          Future<void> createGroup() async {
            final chatId = await appService.createGroupChat(
              name: nameController.text,
              memberIds: selectedIds.toList(),
            );
            if (!sheetContext.mounted || chatId == null) {
              return;
            }
            Navigator.of(sheetContext).pop();
            await onGroupCreated(chatId);
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
                  'Create group chat',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Group name',
                    prefixIcon: Icon(Icons.group),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 300,
                  child: contacts.isEmpty
                      ? const Center(child: Text('Add contacts first'))
                      : ListView.builder(
                          itemCount: contacts.length,
                          itemBuilder: (context, index) {
                            final contact = contacts[index];
                            final userId = contact['user_id'] as String;
                            final selected = selectedIds.contains(userId);
                            return CheckboxListTile(
                              value: selected,
                              onChanged: (value) {
                                setModalState(() {
                                  if (value == true) {
                                    selectedIds.add(userId);
                                  } else {
                                    selectedIds.remove(userId);
                                  }
                                });
                              },
                              title:
                                  Text(contact['name'] as String? ?? 'Unknown'),
                              subtitle: Text(
                                userId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: selectedIds.length >= 2 ? createGroup : null,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Create group'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
