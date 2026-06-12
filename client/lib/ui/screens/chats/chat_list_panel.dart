import 'package:flutter/material.dart';

import '../../../constants/accessibility_ids.dart';
import '../../../local_app_service.dart';
import '../../../themes/apple_liquid/constants/app_colors.dart';
import '../../widgets/empty_state.dart';
import 'create_group_sheet.dart';
import 'group_management_sheet.dart';

/// Left-rail chat list with search header, optional "Chats / Unread"
/// stat cards, and a New-group affordance. Stateless — search input
/// state is owned by the parent's [TextEditingController] (callback-on-
/// change drives parent rebuilds); selection / loading / list contents
/// flow in as props.
///
/// Extracted from `chats_screen.dart` as task #14 of the post-PocketBase
/// hardening plan. Stays with callback-only state lifting (no Provider /
/// InheritedWidget) to match the rest of the codebase.
class ChatListPanel extends StatelessWidget {
  const ChatListPanel({
    super.key,
    required this.chats,
    required this.showStats,
    required this.loading,
    required this.selectedChatId,
    required this.totalChatsCount,
    required this.unreadCount,
    required this.searchController,
    required this.groupNameController,
    required this.appService,
    required this.myUserId,
    required this.onSearchChanged,
    required this.onSelectChat,
    required this.onChatsReloadNeeded,
    required this.onMessagesReloadNeeded,
    required this.initials,
  });

  final List<Map<String, dynamic>> chats;
  final bool showStats;
  final bool loading;
  final String? selectedChatId;
  final int totalChatsCount;
  final int unreadCount;
  final TextEditingController searchController;
  final TextEditingController groupNameController;
  final LocalAppService appService;
  final String? myUserId;
  final VoidCallback onSearchChanged;
  final void Function(String chatId) onSelectChat;
  final Future<void> Function() onChatsReloadNeeded;
  final Future<void> Function(String chatId) onMessagesReloadNeeded;
  final String Function(String? value) initials;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: searchController,
                onChanged: (_) => onSearchChanged(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (showStats) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Chats',
                        value: '$totalChatsCount',
                        accent: AppColors.systemBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Unread',
                        value: '$unreadCount',
                        accent: AppColors.systemOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => showCreateGroupSheet(
                      context: context,
                      appService: appService,
                      nameController: groupNameController,
                      onGroupCreated: (chatId) async {
                        await onChatsReloadNeeded();
                        // Parent owns the mounted check before calling
                        // setState; ChatListPanel just forwards.
                        onSelectChat(chatId);
                      },
                    ),
                    icon: const Icon(Icons.group_add),
                    label: const Text('New group'),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : chats.isEmpty
                  ? Semantics(
                      label: 'No chats',
                      child: const EmptyState(type: 'chats'),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(12, 0, 12,
                          MediaQuery.of(context).padding.bottom + 80),
                      itemCount: chats.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        final isSelected = chat['id'] == selectedChatId;
                        return _ChatTile(
                          chat: chat,
                          isSelected: isSelected,
                          appService: appService,
                          myUserId: myUserId,
                          onTap: () => onSelectChat(chat['id'] as String),
                          onChatsReloadNeeded: onChatsReloadNeeded,
                          onMessagesReloadNeeded: onMessagesReloadNeeded,
                          initials: initials,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.isSelected,
    required this.appService,
    required this.myUserId,
    required this.onTap,
    required this.onChatsReloadNeeded,
    required this.onMessagesReloadNeeded,
    required this.initials,
  });

  final Map<String, dynamic> chat;
  final bool isSelected;
  final LocalAppService appService;
  final String? myUserId;
  final VoidCallback onTap;
  final Future<void> Function() onChatsReloadNeeded;
  final Future<void> Function(String chatId) onMessagesReloadNeeded;
  final String Function(String? value) initials;

  @override
  Widget build(BuildContext context) {
    final unreadCount = chat['unreadCount'] as int? ?? 0;
    final memberCount = chat['memberCount'] as int? ?? 0;
    final isPrivate = chat['isPrivate'] as bool? ?? true;
    final name = chat['name'] as String? ?? 'Chat';

    return Semantics(
      label: AccessibilityIds.chat(name),
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.systemBlue.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? AppColors.systemBlue.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          onTap: onTap,
          onLongPress: isPrivate
              ? null
              : () => showManageGroupSheet(
                    context: context,
                    chat: chat,
                    appService: appService,
                    myUserId: myUserId,
                    onMembersChanged: () async {
                      await onChatsReloadNeeded();
                      await onMessagesReloadNeeded(chat['id'] as String);
                    },
                  ),
          leading: CircleAvatar(
            backgroundColor: AppColors.systemBlue.withValues(alpha: 0.85),
            child: Text(
              initials(chat['name'] as String?),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            ((chat['lastMessage'] as String?)?.isEmpty ?? true)
                ? (isPrivate ? 'No messages yet' : '$memberCount members')
                : chat['lastMessage'] as String,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SizedBox(
            width: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chat['timestamp'] as String? ?? '',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 6),
                if (unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.systemOrange,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
