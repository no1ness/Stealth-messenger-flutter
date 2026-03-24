import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:stealth/helpers/file_bytes.dart';
import 'package:intl/intl.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_chat_bubble.dart'
    as glass;
import 'package:stealth/themes/apple_liquid/widgets/glass_message_input.dart';
import 'package:stealth/ui/widgets/empty_state.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, this.initialChatId});

  final String? initialChatId;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _messageSearchController =
      TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  final ScrollController _messagesScrollController = ScrollController();
  final Map<String, StreamSubscription> _activeSubscriptions = {};

  bool _loading = true;
  bool _loadingMessages = false;
  bool _loadingOlderMessages = false;
  bool _searchInConversation = false;
  bool _isEditingMessage = false;
  bool _hasMoreMessages = true;
  String? _selectedChatId;
  String? _myUserId;
  String? _pendingInitialChatId;
  String? _replyToMessageId;
  String? _replyToMessageText;
  String? _editingMessageId;
  DateTime? _otherLastReadAt;
  bool _isOtherTyping = false;
  Map<String, dynamic>? _pinnedMessage;
  List<Map<String, dynamic>> _chats = const [];
  List<Map<String, dynamic>> _messages = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pendingInitialChatId = widget.initialChatId;
    _bootstrap();
  }

  @override
  void dispose() {
    final selectedChatId = _selectedChatId;
    if (selectedChatId != null) {
      _supabaseService.setTypingStatus(chatId: selectedChatId, isTyping: false);
    }
    _searchController.dispose();
    _groupNameController.dispose();
    _messageSearchController.dispose();
    _messagesScrollController.dispose();
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _myUserId = await _supabaseService.getUserId();
    await _loadChats();
  }

  Future<void> _loadChats() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final rows = await _supabaseService.getChats();
      final me = await _supabaseService.getUserId();
      final chats = <Map<String, dynamic>>[];

      // Предварительная загрузка никнеймов собеседников одним batch-запросом
      final usersToFetch = <String>{};
      for (final row in rows) {
        final members = (row['members'] as List<dynamic>? ?? []).cast<String>();
        final isPrivate = row['is_private'] as bool? ?? false;
        if (members.length == 1) {
          usersToFetch.add(members.first);
        } else if (isPrivate || members.length == 2) {
          final otherId = members.firstWhere(
            (memberId) => memberId != me,
            orElse: () => members.first,
          );
          usersToFetch.add(otherId);
        }
      }
      if (usersToFetch.isNotEmpty) {
        await _supabaseService.getNicknames(usersToFetch);
      }

      // Загрузка деталей чатов в параллельном режиме (Future.wait)
      final chatFutures = rows.map((row) async {
        final members = (row['members'] as List<dynamic>? ?? []).cast<String>();
        final storedName = (row['name'] as String?)?.trim();
        final isPrivate = row['is_private'] as bool? ?? false;
        var title = storedName?.isNotEmpty == true ? storedName! : 'Chat';
        
        if (members.length == 1) {
          title = (await _supabaseService.getNicknameForUser(members.first)) ?? 'Chat';
        } else if (isPrivate || members.length == 2) {
          final otherId = members.firstWhere(
            (memberId) => memberId != me,
            orElse: () => members.first,
          );
          title = (await _supabaseService.getNicknameForUser(otherId)) ?? 'Chat';
        }

        final lastMessage = await _supabaseService.fetchLastMessage(row['id'] as String);
        final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
        final lastSeen = await _supabaseService.getLastSeen(row['id'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final unread = await _supabaseService.countUnreadSince(row['id'] as String, lastSeen);

        return {
          'id': row['id'],
          'name': title,
          'memberCount': members.length,
          'isPrivate': isPrivate,
          'timestamp': createdAt == null ? '' : _formatTimestamp(createdAt),
          'lastMessage': (lastMessage?['content'] as String? ?? '').trim(),
          'unreadCount': unread,
        };
      });

      chats.addAll(await Future.wait(chatFutures));

      if (!mounted) {
        return;
      }

      setState(() {
        _chats = chats;
        _loading = false;
      });

      if (_pendingInitialChatId != null &&
          _chats.any((chat) => chat['id'] == _pendingInitialChatId)) {
        await _selectChat(_pendingInitialChatId!);
      }
      _pendingInitialChatId = null;
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load chats: $error')),
      );
    }
  }

  Future<void> _showCreateGroupSheet() async {
    final contacts = (await _supabaseService.getContacts()).cast<Map<String, dynamic>>();
    final selectedIds = <String>{};
    _groupNameController.clear();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> createGroup() async {
              final chatId = await _supabaseService.createGroupChat(
                name: _groupNameController.text,
                memberIds: selectedIds.toList(),
              );
              if (!context.mounted || chatId == null) {
                return;
              }
              Navigator.of(context).pop();
              await _loadChats();
              if (!mounted) {
                return;
              }
              await _selectChat(chatId);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create group chat',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _groupNameController,
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
                                title: Text(contact['name'] as String? ?? 'Unknown'),
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

  Future<void> _showManageGroupSheet(Map<String, dynamic> chat) async {
    final chatId = chat['id'] as String;
    final contacts =
        (await _supabaseService.getContacts()).cast<Map<String, dynamic>>();
    final members = await _supabaseService.getChatMembers(chatId);
    final myRole = await _supabaseService.getMyRoleInChat(chatId);
    final isAdmin = myRole == 'admin';
    final memberIds = members
        .map<String>((member) => member['user_id'] as String)
        .toSet();
    final availableContacts = contacts
        .where((contact) => !memberIds.contains(contact['user_id'] as String))
        .toList();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> refreshMembers() async {
              final updatedMembers =
                  await _supabaseService.getChatMembers(chatId);
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
                      (contact) => !updatedIds.contains(
                        contact['user_id'] as String,
                      ),
                    ),
                  );
              });
              await _loadChats();
              if (_selectedChatId == chatId) {
                await _loadMessages(chatId);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Manage group',
                    style: Theme.of(context).textTheme.titleLarge,
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final userId = member['user_id'] as String;
                        final role = member['role'] as String? ?? 'member';
                        final canRemove = isAdmin && userId != _myUserId;
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
                                        await _supabaseService.removeMemberFromGroupChat(
                                          chatId: chatId,
                                          memberId: userId,
                                        );
                                      } else if (action == 'promote') {
                                        await _supabaseService.updateGroupMemberRole(
                                          chatId: chatId,
                                          memberId: userId,
                                          role: 'admin',
                                        );
                                      } else if (action == 'demote') {
                                        await _supabaseService.updateGroupMemberRole(
                                          chatId: chatId,
                                          memberId: userId,
                                          role: 'member',
                                        );
                                      }
                                      await refreshMembers();
                                    } catch (error) {
                                      if (!context.mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(context).showSnackBar(
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
                    style: Theme.of(context).textTheme.titleMedium,
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
                                title: Text(contact['name'] as String? ?? 'Unknown'),
                                subtitle: Text(
                                  userId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: FilledButton(
                                  onPressed: () async {
                                    try {
                                      await _supabaseService.addMembersToGroupChat(
                                        chatId: chatId,
                                        memberIds: [userId],
                                      );
                                      await refreshMembers();
                                    } catch (error) {
                                      if (!context.mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _selectChat(String chatId) async {
    if (_selectedChatId != null && _selectedChatId != chatId) {
      await _supabaseService.setTypingStatus(
        chatId: _selectedChatId!,
        isTyping: false,
      );
    }
    setState(() {
      _selectedChatId = chatId;
      _isOtherTyping = false;
      _hasMoreMessages = true;
    });
    await _loadMessages(chatId);
  }

  Future<void> _loadMessages(String chatId) async {
    if (mounted) {
      setState(() {
        _loadingMessages = true;
      });
    }

    final rows = await _supabaseService.getMessages(chatId, limit: 40, offset: 0);
    final otherLastReadAt = await _supabaseService.getOtherLastReadAt(chatId);
    final pinnedMessage = await _supabaseService.getPinnedMessage(chatId);
    if (!mounted) {
      return;
    }

    setState(() {
      _otherLastReadAt = otherLastReadAt;
      _messages = rows
          .cast<Map<String, dynamic>>()
          .map(_toUiMessage)
          .toList()
        ..sort(
          (left, right) => (left['created_at'] as String)
              .compareTo(right['created_at'] as String),
        );
      _loadingMessages = false;
      _hasMoreMessages = rows.length >= 40;
      _pinnedMessage = pinnedMessage;
    });

    await _supabaseService.markChatRead(chatId);
    _subscribeToChatRealtime(chatId);
    _scheduleScrollToBottom();
  }

  Future<void> _loadOlderMessages() async {
    final chatId = _selectedChatId;
    if (chatId == null || _loadingOlderMessages || !_hasMoreMessages) {
      return;
    }

    setState(() {
      _loadingOlderMessages = true;
    });

    final rows = await _supabaseService.getMessages(
      chatId,
      limit: 30,
      offset: _messages.length,
    );
    if (!mounted) {
      return;
    }

    final olderMessages = rows.cast<Map<String, dynamic>>().map(_toUiMessage).toList()
      ..sort(
        (left, right) =>
            (left['created_at'] as String).compareTo(right['created_at'] as String),
      );
    final existingIds = _messages.map((message) => message['id'].toString()).toSet();

    setState(() {
      _messages = [
        ...olderMessages.where(
          (message) => !existingIds.contains(message['id'].toString()),
        ),
        ..._messages,
      ];
      _loadingOlderMessages = false;
      _hasMoreMessages = rows.length >= 30;
    });
  }

  Future<void> _handleSendMessage(String text) async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }

    if (_isEditingMessage && _editingMessageId != null) {
      await _supabaseService.editMessage(
        messageId: _editingMessageId!,
        chatId: chatId,
        content: text,
      );
    } else {
      await _supabaseService.sendMessage(
        chatId: chatId,
        content: text,
        type: 'text',
        replyToId: _replyToMessageId,
      );
    }
    await _supabaseService.setTypingStatus(chatId: chatId, isTyping: false);
    if (mounted) {
      setState(() {
        _replyToMessageId = null;
        _replyToMessageText = null;
        _editingMessageId = null;
        _isEditingMessage = false;
      });
    }
    await _loadMessages(chatId);
  }

  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    final chatId = _selectedChatId;
    if (chatId == null || !mounted) {
      return;
    }

    final messageId = message['id'].toString();
    final isSent = message['isSent'] as bool? ?? false;
    final isPinned = _pinnedMessage?['id']?.toString() == messageId;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _replyToMessageId = messageId;
                    _replyToMessageText = message['message'] as String? ?? '';
                    _editingMessageId = null;
                    _isEditingMessage = false;
                  });
                },
              ),
              ListTile(
                leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(isPinned ? 'Unpin message' : 'Pin message'),
                onTap: () async {
                  Navigator.of(context).pop();
                  if (isPinned) {
                    await _supabaseService.unpinMessage(
                      chatId: chatId,
                      messageId: messageId,
                    );
                  } else {
                    await _supabaseService.pinMessage(
                      chatId: chatId,
                      messageId: messageId,
                    );
                  }
                  await _loadMessages(chatId);
                },
              ),
              if (isSent)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _isEditingMessage = true;
                      _editingMessageId = messageId;
                      _replyToMessageId = null;
                      _replyToMessageText = message['message'] as String? ?? '';
                    });
                  },
                ),
              if (isSent)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _supabaseService.softDeleteMessage(messageId: messageId);
                    await _loadMessages(chatId);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _subscribeToChatRealtime(String chatId) {
    _activeSubscriptions[chatId]?.cancel();
    _activeSubscriptions['typing:$chatId']?.cancel();

    final subscription = _supabaseService.supabase
        .from('messages')
        .stream(primaryKey: const ['id'])
        .eq('chat_id', chatId)
        .listen((records) {
      if (!mounted || _selectedChatId != chatId) {
        return;
      }

      setState(() {
        _messages = records.map(_toUiMessage).toList()
          ..sort(
            (left, right) => (left['created_at'] as String)
                .compareTo(right['created_at'] as String),
          );
      });
      _supabaseService.markChatRead(chatId);
      _refreshReadState();
      _scheduleScrollToBottom();
    });

    _activeSubscriptions[chatId] = subscription;

    // Отдельный поток typing сохраняет UI отзывчивым без перезагрузки сообщений.
    final typingSubscription = _supabaseService.supabase
        .from('chat_members')
        .stream(primaryKey: const ['chat_id', 'user_id'])
        .eq('chat_id', chatId)
        .listen((records) {
      if (!mounted || _selectedChatId != chatId) {
        return;
      }

      final isOtherTyping = records.any(
        (row) =>
            row['user_id'] != _myUserId && (row['typing'] as bool? ?? false),
      );
      setState(() {
        _isOtherTyping = isOtherTyping;
      });
      _refreshReadState();
    });

    _activeSubscriptions['typing:$chatId'] = typingSubscription;
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messagesScrollController.hasClients) {
        _messagesScrollController.animateTo(
          _messagesScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final diffDays = today.difference(thatDay).inDays;

    if (diffDays == 0) {
      return DateFormat('HH:mm').format(dateTime);
    }
    if (diffDays == 1) {
      return 'Yesterday';
    }
    return DateFormat('dd.MM.yyyy').format(dateTime);
  }

  String _formatMessageTime(String? value) {
    final parsed = DateTime.tryParse(value ?? '')?.toLocal();
    return parsed == null ? '' : DateFormat('HH:mm').format(parsed);
  }

  Map<String, dynamic> _toUiMessage(Map<String, dynamic> row) {
    final createdAt = row['created_at'] as String? ?? '';
    final createdAtValue = DateTime.tryParse(createdAt);
    final isSent = row['sender_id'] == _myUserId;
    final isRead = isSent &&
        createdAtValue != null &&
        _otherLastReadAt != null &&
        !createdAtValue.isAfter(_otherLastReadAt!);

    return {
      'id': row['id'],
      'sender_id': row['sender_id'],
      'message': (row['content'] as String? ?? '').trim(),
      'type': (row['message_type'] as String?) ?? 'text',
      'reply_to_id': row['reply_to_id']?.toString(),
      'edited_at': row['edited_at'],
      'created_at': createdAt,
      'timestamp': _formatMessageTime(createdAt),
      'isSent': isSent,
      'isDelivered': isSent,
      'isRead': isRead,
    };
  }

  Future<void> _refreshReadState() async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }
    final otherLastReadAt = await _supabaseService.getOtherLastReadAt(chatId);
    if (!mounted) {
      return;
    }

    setState(() {
      _otherLastReadAt = otherLastReadAt;
      _messages = _messages
          .map(
            (message) => {
              ...message,
              'isRead': (message['isSent'] as bool? ?? false) &&
                  DateTime.tryParse(message['created_at'] as String? ?? '')
                          ?.isAfter(otherLastReadAt ?? DateTime.fromMillisecondsSinceEpoch(0)) ==
                      false,
            },
          )
          .toList();
    });
  }

  String _initials(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '?';
    }

    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final query = _searchController.text.trim().toLowerCase();
    final filteredChats = query.isEmpty
        ? _chats
        : _chats
            .where(
              (chat) => (chat['name'] as String? ?? '')
                  .toLowerCase()
                  .contains(query),
            )
            .toList();

    final currentChat = _chats.firstWhere(
      (chat) => chat['id'] == _selectedChatId,
      orElse: () => const {'name': 'Chat'},
    );
    final messageQuery = _messageSearchController.text.trim().toLowerCase();
    final visibleMessages = messageQuery.isEmpty
        ? _messages
        : _messages
            .where(
              (message) => (message['message'] as String? ?? '')
                  .toLowerCase()
                  .contains(messageQuery),
            )
            .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(
          title: _selectedChatId == null
              ? 'Chats'
              : (currentChat['name'] as String? ?? 'Chat'),
          showBackButton: _selectedChatId != null,
          onBack: () {
            setState(() {
              _selectedChatId = null;
              _searchInConversation = false;
            });
          },
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 960;

          if (isDesktop) {
            return Row(
              children: [
                SizedBox(
                  width: 360,
                  child: _buildChatListPanel(filteredChats, showStats: true),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selectedChatId == null
                      ? const EmptyState(type: 'chats')
                      : _buildConversationPanel(visibleMessages),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 280,
                  child: _buildInsightPanel(filteredChats.length),
                ),
              ],
            );
          }

          if (_selectedChatId == null) {
            return _buildChatListPanel(filteredChats, showStats: false);
          }

          return _buildConversationPanel(visibleMessages);
        },
      ),
    );
  }

  Widget _buildChatListPanel(
    List<Map<String, dynamic>> chats, {
    required bool showStats,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
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
                        value: '${_chats.length}',
                        accent: AppColors.systemBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Unread',
                        value: '${_totalUnreadCount()}',
                        accent: AppColors.systemOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showCreateGroupSheet,
                    icon: const Icon(Icons.group_add),
                    label: const Text('New group'),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : chats.isEmpty
                  ? const EmptyState(type: 'chats')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: chats.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        final isSelected = chat['id'] == _selectedChatId;
                        return _buildChatTile(chat, isSelected);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildChatTile(Map<String, dynamic> chat, bool isSelected) {
    final unreadCount = chat['unreadCount'] as int? ?? 0;
    final memberCount = chat['memberCount'] as int? ?? 0;
    final isPrivate = chat['isPrivate'] as bool? ?? true;

    return AnimatedContainer(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onTap: () => _selectChat(chat['id'] as String),
        onLongPress: isPrivate ? null : () => _showManageGroupSheet(chat),
        leading: CircleAvatar(
          backgroundColor: AppColors.systemBlue.withValues(alpha: 0.85),
          child: Text(
            _initials(chat['name'] as String?),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          chat['name'] as String? ?? 'Chat',
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
    );
  }

  Widget _buildConversationPanel(List<Map<String, dynamic>> visibleMessages) {
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (_pinnedMessage != null)
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
                      _pinnedMessage?['content'] as String? ?? '',
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
                  controller: _messageSearchController,
                  onChanged: (_) => setState(() {
                    _searchInConversation =
                        _messageSearchController.text.trim().isNotEmpty;
                  }),
                  decoration: InputDecoration(
                    hintText: 'Search in conversation',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_searchInConversation) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    _messageSearchController.clear();
                    setState(() {
                      _searchInConversation = false;
                    });
                  },
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
                  controller: _messagesScrollController,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  itemCount: visibleMessages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      if (_loadingOlderMessages) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (_hasMoreMessages) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: OutlinedButton(
                              onPressed: _loadOlderMessages,
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
                        : _messages.cast<Map<String, dynamic>?>().firstWhere(
                              (candidate) => candidate?['id'].toString() == replyToId,
                              orElse: () => null,
                            );

                    return GestureDetector(
                      onLongPress: () => _showMessageActions(message),
                      child: glass.GlassChatBubble(
                        message: '${message['message'] as String? ?? ''}${message['edited_at'] != null ? ' (edited)' : ''}',
                        timestamp: message['timestamp'] as String?,
                        isDelivered: message['isDelivered'] as bool?,
                        isRead: message['isRead'] as bool?,
                        replyPreview: repliedMessage == null
                            ? null
                            : _buildReplyPreview(
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
        _buildConversationFooter(),
      ],
    );
  }

  Widget _buildConversationFooter() {
    // Футер объединяет полосу прогресса с полем ввода, чтобы чат
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyToMessageText != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.systemBlue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_isEditingMessage ? 'Editing' : 'Replying to'}: $_replyToMessageText',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _replyToMessageId = null;
                            _replyToMessageText = null;
                            _editingMessageId = null;
                            _isEditingMessage = false;
                          });
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _messages.isEmpty
                          ? 0.12
                          : _messages.length.clamp(1, 50) / 50,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                      color: AppColors.systemBlue,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_messages.length} msgs',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              if (_isOtherTyping) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Typing...',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.systemGreen,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
        GlassMessageInput(
          onSendMessage: _handleSendMessage,
          onAttachment: _handleAttachment,
          onVoiceRecorded: _handleVoiceRecorded,
          onTyping: (isTyping) async {
            final chatId = _selectedChatId;
            if (chatId == null) {
              return;
            }
            await _supabaseService.setTypingStatus(
              chatId: chatId,
              isTyping: isTyping,
            );
          },
        ),
      ],
    );
  }

  Widget _buildReplyPreview(String text) {
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

  Widget _buildInsightPanel(int visibleChats) {
    final theme = Theme.of(context);
    final values = [
      _messages.isEmpty ? 0.18 : 0.68,
      visibleChats == 0 ? 0.12 : 0.54,
      kIsWeb ? 0.74 : 0.49,
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session insight', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _InsightTile(
            label: 'Realtime sync',
            value: 'Active',
            accent: AppColors.systemGreen,
          ),
          const SizedBox(height: 10),
          _InsightTile(
            label: 'Platform',
            value: kIsWeb ? 'Web' : 'Mobile',
            accent: AppColors.systemBlue,
          ),
          const SizedBox(height: 10),
          _InsightTile(
            label: 'Current user',
            value: _myUserId == null ? 'Unknown' : _myUserId!.substring(0, 8),
            accent: AppColors.systemOrange,
          ),
          const SizedBox(height: 22),
          Text('Load profile', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values
                  .map(
                    (value) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          height: 110 * value,
                          decoration: BoxDecoration(
                            color: AppColors.systemBlue.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  int _totalUnreadCount() {
    return _chats.fold<int>(
      0,
      (sum, chat) => sum + (chat['unreadCount'] as int? ?? 0),
    );
  }

  Future<void> _handleAttachment() async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected file is not readable')),
      );
      return;
    }

    final publicUrl = await _supabaseService.uploadAttachmentBytes(
      bytes: bytes,
      fileName: file.name,
      chatId: chatId,
    );

    if (publicUrl == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload attachment')),
      );
      return;
    }

    await _supabaseService.sendMessage(
      chatId: chatId,
      content: publicUrl,
      type: _resolveAttachmentType(file.name),
    );
    await _loadMessages(chatId);
  }

  Future<void> _handleVoiceRecorded(String filePath) async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }

    final bytes = await readFileBytes(filePath);
    final segments = filePath.split(RegExp(r'[\\/]'));
    final fileName = segments.isEmpty ? 'voice_note.m4a' : segments.last;
    if (bytes == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice file is not readable')),
      );
      return;
    }

    final publicUrl = await _supabaseService.uploadAttachmentBytes(
      bytes: bytes,
      fileName: fileName,
      chatId: chatId,
    );
    if (publicUrl == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload voice message')),
      );
      return;
    }

    await _supabaseService.sendMessage(
      chatId: chatId,
      content: publicUrl,
      type: 'audio',
    );
    await _loadMessages(chatId);
  }

  String _resolveAttachmentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return 'image';
    }
    if (lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg')) {
      return 'audio';
    }
    return 'file';
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

class _InsightTile extends StatelessWidget {
  const _InsightTile({
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
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
