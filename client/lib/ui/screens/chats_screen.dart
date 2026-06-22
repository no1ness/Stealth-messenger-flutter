import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:stealth/helpers/file_bytes.dart';
import 'package:intl/intl.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:stealth/ui/screens/chats/conversation_footer.dart';
import 'package:stealth/ui/screens/chats/conversation_panel.dart';

import 'package:stealth/ui/screens/chats/group_management_sheet.dart';
import 'package:stealth/ui/screens/chats/chat_search_bar.dart';


import 'package:stealth/ui/screens/chats/telegram_sidebar.dart';
import 'package:stealth/ui/screens/chats/telegram_header.dart';
import 'package:stealth/ui/widgets/empty_state.dart';
import 'package:stealth/helpers/responsive_breakpoints.dart';
import 'package:stealth/p2p_service.dart';

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
  final LocalAppService _appService = LocalAppService();
  final ScrollController _messagesScrollController = ScrollController();
  final Map<String, StreamSubscription> _activeSubscriptions = {};
  Timer? _messageSearchDebounce;
  Timer? _loadChatsDebounce;
  List<Map<String, dynamic>> _filteredChats = const [];
  List<Map<String, dynamic>> _filteredMessages = const [];
  List<Map<String, dynamic>> _pinnedChats = const [];
  List<Map<String, dynamic>> _recentChats = const [];

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
    _listenToP2PMessages();
  }

  void _listenToP2PMessages() {
    _activeSubscriptions['p2p_global'] =
        P2PService.instance.onMessage.listen((event) async {
      final chatId = event['chat_id'] as String;
      final rawMessage = Map<String, dynamic>.from(event['message'] as Map);
      final message = await _appService.decryptRawMessage(rawMessage);

      if (mounted && _selectedChatId == chatId) {
        setState(() {
          final uiMsg = _toUiMessage(message);
          // Prevent duplicates if local and P2P delivery arrive nearly at the same time.
          if (!_messages.any((m) => m['id'] == uiMsg['id'])) {
            _messages = [..._messages, uiMsg]..sort(
                (left, right) => (left['created_at'] as String)
                    .compareTo(right['created_at'] as String),
              );
            _updateFilters();
            _scheduleScrollToBottom();
          }
        });
      }
      // If the chat is in the list, we might want to update last message preview
      _debouncedLoadChats();
    });
  }

  @override
  void dispose() {
    final selectedChatId = _selectedChatId;
    if (selectedChatId != null) {
      _appService.setTypingStatus(chatId: selectedChatId, isTyping: false);
    }
    _messageSearchDebounce?.cancel();
    _loadChatsDebounce?.cancel();
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
    _myUserId = await _appService.getUserId();
    await _loadChats();
  }

  Future<void> _loadChats() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final rows = await _appService.getChats();
      final me = await _appService.getUserId();
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
        await _appService.getNicknames(usersToFetch);
      }

      // Загрузка деталей чатов в параллельном режиме (Future.wait)
      final chatFutures = rows.map((row) async {
        final members = (row['members'] as List<dynamic>? ?? []).cast<String>();
        final storedName = (row['name'] as String?)?.trim();
        final isPrivate = row['is_private'] as bool? ?? false;
        var title = storedName?.isNotEmpty == true ? storedName! : 'Чат';

        if (members.length == 1) {
          title =
              (await _appService.getNicknameForUser(members.first)) ?? 'Чат';
        } else if (isPrivate || members.length == 2) {
          final otherId = members.firstWhere(
            (memberId) => memberId != me,
            orElse: () => members.first,
          );
          title = (await _appService.getNicknameForUser(otherId)) ?? 'Чат';
        }

        final lastMessage =
            await _appService.fetchLastMessage(row['id'] as String);
        final createdAt =
            DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
        final lastSeen = await _appService.getLastSeen(row['id'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final unread =
            await _appService.countUnreadSince(row['id'] as String, lastSeen);

        final isPinned = row['isPinned'] as bool? ?? false;

        return {
          'id': row['id'],
          'name': title,
          'memberCount': members.length,
          'isPrivate': isPrivate,
          'isPinned': isPinned,
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
        _updateFilters();
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
      if (mounted) {
        TgSnackBar.show(
          context,
          'Ошибка загрузки чатов: $error',
          isError: true,
        );
      }
    }
  }

  Future<void> _selectChat(String chatId) async {
    if (_selectedChatId != null && _selectedChatId != chatId) {
      await _appService.setTypingStatus(
        chatId: _selectedChatId!,
        isTyping: false,
      );
    }
    setState(() {
      _selectedChatId = chatId;
      _isOtherTyping = false;
      _hasMoreMessages = true;
    });

    // Start P2P connection attempt.
    unawaited(P2PService.instance.connectToPeer(chatId));

    await _loadMessages(chatId);
  }

  Future<void> _loadMessages(String chatId) async {
    if (mounted) {
      setState(() {
        _loadingMessages = true;
      });
    }

    final rows = await _appService.getMessages(chatId, limit: 40, offset: 0);
    final otherLastReadAt = await _appService.getOtherLastReadAt(chatId);
    final pinnedMessage = await _appService.getPinnedMessage(chatId);
    if (!mounted) {
      return;
    }

    setState(() {
      _otherLastReadAt = otherLastReadAt;
      _messages = rows.cast<Map<String, dynamic>>().map(_toUiMessage).toList()
        ..sort(
          (left, right) => (left['created_at'] as String)
              .compareTo(right['created_at'] as String),
        );
      _loadingMessages = false;
      _hasMoreMessages = rows.length >= 40;
      _pinnedMessage = pinnedMessage;
      _updateFilters();
    });

    await _appService.markChatRead(chatId);
    _subscribeToChatP2P(chatId);
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

    final rows = await _appService.getMessages(
      chatId,
      limit: 30,
      offset: _messages.length,
    );
    if (!mounted) {
      return;
    }

    final olderMessages =
        rows.cast<Map<String, dynamic>>().map(_toUiMessage).toList()
          ..sort(
            (left, right) => (left['created_at'] as String)
                .compareTo(right['created_at'] as String),
          );
    final existingIds =
        _messages.map((message) => message['id'].toString()).toSet();

    setState(() {
      _messages = [
        ...olderMessages.where(
          (message) => !existingIds.contains(message['id'].toString()),
        ),
        ..._messages,
      ];
      _loadingOlderMessages = false;
      _hasMoreMessages = rows.length >= 30;
      _updateFilters();
    });
  }

  Future<void> _handleSendMessage(String text) async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }

    if (_isEditingMessage && _editingMessageId != null) {
      await _appService.editMessage(
        messageId: _editingMessageId!,
        chatId: chatId,
        content: text,
      );
      await _loadMessages(chatId);
    } else {
      // Optimistic UI update: add message immediately to local state
      final tempMessage = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
        'chat_id': chatId,
        'sender_id': _myUserId,
        'content': text,
        'message_type': 'text',
        'reply_to_id': _replyToMessageId,
        'created_at': DateTime.now().toIso8601String(),
        'metadata': {},
      };

      if (mounted) {
        setState(() {
          final uiMsg = _toUiMessage(tempMessage);
          if (!_messages.any((m) => m['id'] == uiMsg['id'])) {
            _messages = [..._messages, uiMsg]..sort(
                (left, right) => (left['created_at'] as String)
                    .compareTo(right['created_at'] as String),
              );
            _updateFilters();
            _scheduleScrollToBottom();
          }
        });
      }

      await _appService.sendMessage(
        chatId: chatId,
        content: text,
        type: 'text',
        replyToId: _replyToMessageId,
      );
      await _loadMessages(chatId);
    }
    await _appService.setTypingStatus(chatId: chatId, isTyping: false);
    if (mounted) {
      setState(() {
        _replyToMessageId = null;
        _replyToMessageText = null;
        _editingMessageId = null;
        _isEditingMessage = false;
      });
    }
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
                title: const Text('Ответить'),
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
                leading:
                    Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(isPinned ? 'Открепить' : 'Закрепить'),
                onTap: () async {
                  Navigator.of(context).pop();
                  if (isPinned) {
                    await _appService.unpinMessage(chatId: chatId);
                  } else {
                    await _appService.pinMessage(
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
                  title: const Text('Редактировать'),
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
                  title: const Text('Удалить'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _appService.softDeleteMessage(messageId: messageId);
                    await _loadMessages(chatId);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _subscribeToChatP2P(String chatId) {
    _activeSubscriptions[chatId]?.cancel();
    _activeSubscriptions['typing:$chatId']?.cancel();
    // Subscribe to P2P signaling events (offer/answer/candidate) via PocketBase.
    _appService.subscribeP2PSignaling(chatId);
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
      return 'Вчера';
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
      'metadata': row['metadata'],
    };
  }

  void _updateFilters() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredChats = _chats;
      _pinnedChats =
          _chats.where((c) => c['isPinned'] as bool? ?? false).toList();
      _recentChats =
          _chats.where((c) => !(c['isPinned'] as bool? ?? false)).toList();
    } else {
      _filteredChats = _chats
          .where(
            (chat) =>
                (chat['name'] as String? ?? '').toLowerCase().contains(query),
          )
          .toList();
      _pinnedChats = const [];
      _recentChats = _filteredChats;
    }

    final messageQuery = _messageSearchController.text.trim().toLowerCase();
    _filteredMessages = messageQuery.isEmpty
        ? _messages
        : _messages
            .where(
              (message) => (message['message'] as String? ?? '')
                  .toLowerCase()
                  .contains(messageQuery),
            )
            .toList();
  }

  void _debouncedLoadChats() {
    _loadChatsDebounce?.cancel();
    _loadChatsDebounce = Timer(
      const Duration(milliseconds: 500),
      () {
        if (mounted) {
          _loadChats();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    super.build(context);

    final currentChat = _chats.firstWhere(
      (chat) => chat['id'] == _selectedChatId,
      orElse: () => const {'name': 'Чат'},
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: TgAppBar(
        isLargeTitle: _selectedChatId == null,
        titleWidget: _selectedChatId == null
            ? const Text(
                'Чаты',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentChat['name'] as String? ?? 'Чат',
                    style: TgTypography.headline.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color:
                              P2PService.instance.isP2PReady(_selectedChatId!)
                                  ? c.green
                                  : c.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        P2PService.instance.isP2PReady(_selectedChatId!)
                            ? 'P2P'
                            : 'Локально',
                        style: TgTypography.caption2.copyWith(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        showBackButton: _selectedChatId != null,
        onBack: () {
          setState(() {
            _selectedChatId = null;
            _searchInConversation = false;
          });
        },
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop =
              ResponsiveBreakpoints.isDesktop(constraints.maxWidth);

          if (isDesktop) {
            return Row(
              children: [
                SizedBox(
                  width: 320,
                  child: TelegramSidebar(
                    chats: _filteredChats,
                    selectedChatId: _selectedChatId,
                    onChatSelected: (chatId) => _selectChat(chatId),
                    onContactSelected: (contact) async {
                      final userId = (contact['user_id'] ?? contact['contact_user_id'])?.toString();
                      if (userId != null) {
                        final chatId = await _appService.findOrCreatePrivateChatWith(userId);
                        if (chatId != null && mounted) {
                          await _loadChats();
                          await _selectChat(chatId);
                        }
                      }
                    },
                    loading: _loading,
                  ),
                ),
                Expanded(
                  child: _selectedChatId == null
                      ? const StealthEmptyState.chats()
                      : Column(
                          children: [
                            TelegramHeader(
                              chatName: currentChat['name'] as String? ?? 'Чат',
                              chatId: _selectedChatId!,
                              onBack: null,
                            ),
                            Expanded(
                              child: _buildConversationPanel(_filteredMessages),
                            ),
                          ],
                        ),
                ),
              ],
            );
          }

          if (_selectedChatId == null) {
            return _buildChatListPanel(_filteredChats);
          }

          return _buildConversationPanel(_filteredMessages);
        },
      ),
    );
  }

  Widget _buildChatListPanel(List<Map<String, dynamic>> chats) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: ChatSearchBar(
            controller: _searchController,
            onSearchChanged: () {
              if (mounted) {
                setState(() {
                  _updateFilters();
                });
              }
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Column(count: 6)
              : chats.isEmpty
                  ? Semantics(
                      label: 'Нет чатов',
                      child: const StealthEmptyState.chats(),
                    )
                  : _pinnedChats.isEmpty && _recentChats.isEmpty
                      ? ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            0,
                            0,
                            MediaQuery.of(context).padding.bottom +
                                TgSpacing.bottomBarOverlap,
                          ),
                          itemCount: chats.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: TgSpacing.xs),
                          itemBuilder: (context, index) {
                            final chat = chats[index];
                            final isSelected = chat['id'] == _selectedChatId;
                            return _buildTgChatTile(chat, isSelected);
                          },
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            0,
                            0,
                            MediaQuery.of(context).padding.bottom +
                                TgSpacing.bottomBarOverlap,
                          ),
                          children: [
                            if (_pinnedChats.isNotEmpty) ...[
                              TgSectionHeader(
                                title: 'Закреплённые',
                                count: _pinnedChats.length,
                              ),
                              ..._pinnedChats.map((chat) {
                                final isSelected =
                                    chat['id'] == _selectedChatId;
                                return _buildTgChatTile(chat, isSelected);
                              }),
                            ],
                            if (_recentChats.isNotEmpty) ...[
                              TgSectionHeader(
                                title: 'Последние',
                                count: _recentChats.length,
                              ),
                              ..._recentChats.map((chat) {
                                final isSelected =
                                    chat['id'] == _selectedChatId;
                                return _buildTgChatTile(chat, isSelected);
                              }),
                            ],
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _buildTgChatTile(Map<String, dynamic> chat, bool isSelected) {
    final isPrivate = chat['isPrivate'] as bool? ?? true;
    return TgChatTile(
      chat: chat,
      isSelected: isSelected,
      isSent: chat['isSent'] as bool?,
      isRead: chat['isRead'] as bool?,
      isDelivered: chat['isDelivered'] as bool?,
      isVerified: chat['isVerified'] as bool? ?? false,
      isPinned: chat['isPinned'] as bool? ?? false,
      onTap: () => _selectChat(chat['id'] as String),
      onLongPress: isPrivate
          ? null
          : () => showManageGroupSheet(
                context: context,
                chat: chat,
                appService: _appService,
                myUserId: _myUserId,
                onMembersChanged: () async {
                  await _loadChats();
                  if (_selectedChatId == chat['id']) {
                    await _loadMessages(chat['id'] as String);
                  }
                },
              ),
    );
  }

  Widget _buildConversationPanel(List<Map<String, dynamic>> visibleMessages) {
    return ConversationPanel(
      loadingMessages: _loadingMessages,
      loadingOlderMessages: _loadingOlderMessages,
      hasMoreMessages: _hasMoreMessages,
      pinnedMessage: _pinnedMessage,
      messageSearchController: _messageSearchController,
      searchInConversation: _searchInConversation,
      onSearchChanged: () {
        _messageSearchDebounce?.cancel();
        _messageSearchDebounce = Timer(
          const Duration(milliseconds: 200),
          () {
            if (mounted) {
              setState(() {
                _searchInConversation =
                    _messageSearchController.text.trim().isNotEmpty;
                _updateFilters();
              });
            }
          },
        );
      },
      onSearchCleared: () {
        _messageSearchController.clear();
        setState(() {
          _searchInConversation = false;
          _updateFilters();
        });
      },
      scrollController: _messagesScrollController,
      messages: _messages,
      visibleMessages: visibleMessages,
      onLoadOlder: _loadOlderMessages,
      onMessageLongPress: _showMessageActions,
      appService: _appService,
      chatId: _selectedChatId!,
      footer: ConversationFooter(
        replyToMessageText: _replyToMessageText,
        isEditingMessage: _isEditingMessage,
        messagesCount: _messages.length,
        isOtherTyping: _isOtherTyping,
        onCancelReplyOrEdit: () {
          setState(() {
            _replyToMessageId = null;
            _replyToMessageText = null;
            _editingMessageId = null;
            _isEditingMessage = false;
          });
        },
        onSendMessage: _handleSendMessage,
        onAttachment: _handleAttachment,
        onVoiceRecorded: _handleVoiceRecorded,
        onTypingChanged: (isTyping) async {
          final chatId = _selectedChatId;
          if (chatId == null) {
            return;
          }
          await _appService.setTypingStatus(
            chatId: chatId,
            isTyping: isTyping,
          );
        },
      ),
    );
  }

  Future<void> _handleAttachment() async {
    final chatId = _selectedChatId;
    if (chatId == null) {
      return;
    }

    final result = await FilePicker.pickFiles(
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
      TgSnackBar.show(
        context,
        'Выбранный файл не читается',
        isError: true,
      );
      return;
    }

    final publicUrl = await _appService.uploadAttachmentBytes(
      bytes: bytes,
      fileName: file.name,
      chatId: chatId,
      encrypt: true,
    );

    if (publicUrl == null) {
      if (!mounted) {
        return;
      }
      TgSnackBar.show(
        context,
        'Ошибка загрузки вложения',
        isError: true,
      );
      return;
    }

    await _appService.sendMessage(
      chatId: chatId,
      content: publicUrl,
      type: _resolveAttachmentType(file.name),
      metadataOverride: {'file_encrypted': true},
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
      TgSnackBar.show(
        context,
        'Голосовой файл не читается',
        isError: true,
      );
      return;
    }

    final publicUrl = await _appService.uploadAttachmentBytes(
      bytes: bytes,
      fileName: fileName,
      chatId: chatId,
      encrypt: true,
    );
    if (publicUrl == null) {
      if (!mounted) {
        return;
      }
      TgSnackBar.show(
        context,
        'Ошибка загрузки голосового сообщения',
        isError: true,
      );
      return;
    }

    await _appService.sendMessage(
      chatId: chatId,
      content: publicUrl,
      type: 'audio',
      metadataOverride: {'file_encrypted': true},
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
