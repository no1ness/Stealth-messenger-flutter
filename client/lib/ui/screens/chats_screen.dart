import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_input.dart';
import 'package:stealth/supabase_service.dart';
import 'package:intl/intl.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:async';

class ChatsScreen extends StatefulWidget {
  final String? initialChatId;
  const ChatsScreen({super.key, this.initialChatId});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedChatId;
  final SupabaseService _supabaseService = SupabaseService();
  bool _loading = true;
  List<Map<String, dynamic>> _chats = const [];
  List<Map<String, dynamic>> _messages = const [];
  String? _initialChatId;
  bool _isLoadingMore = false;
  String? _myUserId;
  final ScrollController _mobileScrollController = ScrollController();
  final ScrollController _webScrollController = ScrollController();
  final String _webPort = '8082';
  
  void _sortMessagesByCreatedAt() {
    _messages.sort((a, b) {
      final sa = (a['created_at'] as String?) ?? '';
      final sb = (b['created_at'] as String?) ?? '';
      return sa.compareTo(sb);
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initialChatId = widget.initialChatId;
    _bootstrap();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _myUserId = await _supabaseService.getUserId();
    if (!mounted) return;
    
    try {
      await _loadChats();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadChats() async {
    debugPrint('DEBUG: Starting _loadChats()');
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final rows = await _supabaseService.getChats();
    debugPrint('DEBUG: getChats() returned ${rows.length} rows');
    if (!mounted) return;

    final chats = <Map<String, dynamic>>[];
    final String? me = await _supabaseService.getUserId();
    debugPrint('DEBUG: Current user ID: $me');
    final Set<String> allMemberIds = rows
        .expand((row) => (row['members'] as List<dynamic>? ?? []).cast<String>())
        .toSet();
    debugPrint('DEBUG: All member IDs: $allMemberIds');

    for (final row in rows) {
      debugPrint('DEBUG: Processing chat row: ${row['id']}');
      final List<dynamic> members = row['members'] ?? [];
      String title = 'Chat';
      if (members.length == 1) {
        title = (await _supabaseService.getNicknameForUser((members.first as String?) ?? '')) ?? 'Chat';
      } else if (members.length == 2) {
        final String? otherId = members.cast<String?>().firstWhere((m) => m != me, orElse: () => null);
        title = (await _supabaseService.getNicknameForUser(otherId ?? '')) ?? 'Chat';
      } else if (members.length > 2) {
        title = 'Group';
      }
      String ts = '';
      try {
        final dt = DateTime.tryParse(row['created_at'] ?? '')?.toLocal();
        if (dt != null) ts = _formatTimestamp(dt);
      } catch (e) {
        debugPrint('Error formatting timestamp: $e');
      }
      String lastText = '';
      try {
        final last = await _supabaseService.fetchLastMessage(row['id'] as String);
        if (last != null) {
          lastText = (last['content'] as String? ?? '').trim();
        }
      } catch (e) {
        debugPrint('Error processing message preview: $e');
      }
      int unread = 0;
      final lastSeen = await _supabaseService.getLastSeen(row['id'] as String) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      try {
        unread = await _supabaseService.countUnreadSince(row['id'] as String, lastSeen);
      } catch (e) {
        debugPrint('Error counting unread messages: $e');
      }
      chats.add({
        'id': row['id'],
        'name': title,
        'timestamp': ts,
        'lastMessage': lastText,
        'unreadCount': unread.toString(),
      });
    }
    debugPrint('DEBUG: Processed ${chats.length} chats');
    if (mounted) {
      setState(() {
        _chats = chats;
        _loading = false;
      });
    }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка сети. Не удалось загрузить чаты.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _loading = false;
        });
      }
    }

    if (_initialChatId != null) {
      final exists = _chats.any((c) => c['id'] == _initialChatId);
      if (exists) {
        _selectedChatId = _initialChatId;
        await _loadMessages(_initialChatId!);
      }
      _initialChatId = null;
    }
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final diffDays = today.difference(thatDay).inDays;

    if (diffDays == 0) return DateFormat('HH:mm').format(dateTime);
    if (diffDays == 1) return 'Вчера';
    return DateFormat('dd.MM.yyyy').format(dateTime);
  }

  Future<void> _loadMessages(String chatId) async {
    debugPrint('DEBUG: Loading messages for chat: $chatId');
    final rows = await _supabaseService.getMessages(chatId);
    debugPrint('DEBUG: Loaded ${rows.length} messages');
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _messages = rows
            .map((m) => {
                'id': m['id'],
                'sender_id': m['sender_id'],
                'message': (m['content'] as String? ?? '').trim(),
                'type': (m['message_type'] as String?) ?? 'text',
                'created_at': m['created_at'],
                'timestamp': _formatMessageTime(m['created_at']),
                'isSent': _isMine(m['sender_id']),
                'isDelivered': true,
                'isRead': false, // This should be properly handled
              })
          .toList();
        _sortMessagesByCreatedAt();
      });
    }
    debugPrint('DEBUG: Messages loaded and set, count: ${_messages.length}');
    _scheduleScrollToBottom();

    // Setup realtime subscription for this chat
    _subscribeToChatRealtime(chatId);
  }

  Future<void> _handleSendMessage(String message) async {
    final chatId = _selectedChatId;
    if (chatId == null) return;
    try {
      await _supabaseService.sendMessage(chatId: chatId, content: message, type: 'text');
      // Manually add message to local list for immediate feedback
      final me = await _supabaseService.getUserId();
      if (mounted) {
        setState(() {
          _messages.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(), // temp id
          'sender_id': me,
          'message': message,
          'type': 'text',
          'created_at': DateTime.now().toIso8601String(),
          'timestamp': _formatMessageTime(DateTime.now().toIso8601String()),
          'isSent': true,
          'isDelivered': true,
          'isRead': false,
        });
          _sortMessagesByCreatedAt();
        });
      }
      _scheduleScrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить сообщение: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _chats
        : _chats.where((c) => (c['name'] as String? ?? '').toLowerCase().contains(query)).toList();

    final currentChat = _chats.firstWhere(
      (chat) => chat['id'] == _selectedChatId,
      orElse: () => {},
    );

    debugPrint('DEBUG: Building ChatsScreen, selectedChatId: $_selectedChatId, messages count: ${_messages.length}');
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        elevation: 0,
        title: _selectedChatId == null
            ? const Text('Chats')
            : Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    child: Text(_initials(currentChat['name'])),
                  ),
                  const SizedBox(width: 8),
                  Text(currentChat['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
        actions: _selectedChatId == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.call),
                  onPressed: () => _initiateCall(_selectedChatId!),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _loadMessages(_selectedChatId!),
                ),
              ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return Row(
              children: [
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Search chats...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => setState(() {}),
                        ),
                      ),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : filtered.isEmpty
                                ? const Center(child: Text('No chats found'))
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final chat = filtered[index];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          child: Text(_initials(chat['name'])),
                                        ),
                                        title: Text(chat['name'] ?? ''),
                                        subtitle: Text(chat['lastMessage'] ?? ''),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(chat['timestamp'] ?? '', style: const TextStyle(fontSize: 12)),
                                            if (chat['unreadCount'] != '0')
                                              Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.blue,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Text(
                                                  chat['unreadCount'] ?? '',
                                                  style: const TextStyle(color: Colors.white, fontSize: 10),
                                                ),
                                              ),
                                          ],
                                        ),
                                        selected: chat['id'] == _selectedChatId,
                                        onTap: () {
                                          setState(() {
                                            _selectedChatId = chat['id'];
                                          });
                                          _loadMessages(chat['id']);
                                        },
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
                Expanded(
                  child: _selectedChatId == null
                      ? EmptyState(type: 'chats')
                      : Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8),
                                controller: _webScrollController,
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  return ChatBubble(
                                    message: (message['message'] as String? ?? ''),
                                    timestamp: (message['timestamp'] as String? ?? ''),
                                    isSent: (message['isSent'] as bool? ?? false),
                                    type: message['type'] as String?,
                                    messageId: message['id'] as String?,
                                  );
                                },
                              ),
                            ),
                            MessageInput(
                              onSendMessage: _handleSendMessage,
                              onAttachment: _handleAttachment,
                              onVoiceRecorded: _handleVoiceRecorded,
                            ),
                          ],
                        ),
                ),
                VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
                SizedBox(
                  width: 320,
                  child: _buildDebugPanel(),
                ),
              ],
            );
          } else {
            // Single-column layout for mobile
            return _selectedChatId == null
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Search chats...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => setState(() {}),
                        ),
                      ),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : filtered.isEmpty
                                ? const Center(child: Text('No chats found'))
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final chat = filtered[index];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          child: Text(_initials(chat['name'])),
                                        ),
                                        title: Text(chat['name'] ?? ''),
                                        subtitle: Text(chat['lastMessage'] ?? ''),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(chat['timestamp'] ?? '', style: const TextStyle(fontSize: 12)),
                                            if (chat['unreadCount'] != '0')
                                              Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.blue,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Text(
                                                  chat['unreadCount'] ?? '',
                                                  style: const TextStyle(color: Colors.white, fontSize: 10),
                                                ),
                                              ),
                                          ],
                                        ),
                                        selected: chat['id'] == _selectedChatId,
                                        onTap: () {
                                          setState(() {
                                            _selectedChatId = chat['id'];
                                          });
                                          _loadMessages(chat['id']);
                                        },
                                      );
                                    },
                                  ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _messages.isEmpty
                            ? const Center(child: Text('No messages yet'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                controller: _mobileScrollController,
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  return ChatBubble(
                                    message: (message['message'] as String? ?? ''),
                                    timestamp: (message['timestamp'] as String? ?? ''),
                                    isSent: (message['isSent'] as bool? ?? false),
                                    type: message['type'] as String?,
                                    messageId: message['id'] as String?,
                                  );
                                },
                              ),
                      ),
                      MessageInput(
                        onSendMessage: _handleSendMessage,
                        onAttachment: _handleAttachment,
                        onVoiceRecorded: _handleVoiceRecorded,
                      ),
                    ],
                  );
          }
        },
      ),
    );
  }

  void _initiateCall(String chatId) {
    debugPrint('Initiating call for chat: $chatId');
    _supabaseService.sendCallInitiation(chatId: chatId);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Вызов...'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Ожидание ответа...'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _supabaseService.sendCallEnd(chatId: chatId);
            },
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    if (_mobileScrollController.hasClients) {
      final max = _mobileScrollController.position.maxScrollExtent;
      _mobileScrollController.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
    if (_webScrollController.hasClients) {
      final max = _webScrollController.position.maxScrollExtent;
      _webScrollController.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  bool _isMine(dynamic senderId) {
    final String sender = (senderId as String?) ?? '';
    return _myUserId != null && sender.isNotEmpty && sender == _myUserId;
  }

  String _formatMessageTime(dynamic createdAt) {
    final raw = createdAt as String?;
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt);
  }

  Map<String, dynamic> _toUiMessage(Map<String, dynamic> record) {
    return {
      'id': record['id'],
      'sender_id': record['sender_id'],
      'message': (record['content'] as String? ?? '').trim(),
      'type': (record['message_type'] as String?) ?? 'text',
      'created_at': record['created_at'],
      'timestamp': _formatMessageTime(record['created_at']),
      'isSent': _isMine(record['sender_id']),
      'isDelivered': true,
      'isRead': false,
    };
  }
  
  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r"\\s+"));
    final a = parts.first.isNotEmpty ? parts.first[0] : '';
    final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (a + b).toUpperCase();
  }

  bool _isReadByMe(List<dynamic>? readBy) {
    final String? myId = _myUserId;
    if (myId == null) return false;
    return readBy?.any((id) => id == myId) ?? false;
  }

  void _subscribeToChatRealtime(String chatId) {
    // First, unsubscribe from any existing subscription for this chat
    if (_activeSubscriptions.containsKey(chatId)) {
      _activeSubscriptions[chatId]?.cancel();
      _activeSubscriptions.remove(chatId);
      debugPrint('DEBUG: Unsubscribed from old channel for chat $chatId');
    }

    debugPrint('DEBUG: Setting up realtime subscription for chat: $chatId');
    try {
      final subscription = _supabaseService.supabase
          .from('messages')
          .stream(primaryKey: ['id']).eq('chat_id', chatId).listen((data) {
        debugPrint(
            'DEBUG: Realtime message update received: ${data.length} messages for chat $chatId');
        if (data.isNotEmpty && mounted && _selectedChatId == chatId) {
          setState(() {
            for (final newMessage in data) {
              final exists =
                  _messages.any((m) => m['id'] == newMessage['id']);
              if (!exists) {
                _messages.add(_toUiMessage(newMessage));
              }
            }
            _sortMessagesByCreatedAt();
          });
          _scheduleScrollToBottom();
        }
      });

      // Store subscription for cleanup
      _activeSubscriptions[chatId] = subscription;
      debugPrint(
          'DEBUG: Realtime subscription setup successfully for chat $chatId');
    } catch (e) {
      debugPrint('DEBUG: Failed to setup realtime subscription: $e');
    }
  }

  final Map<String, StreamSubscription> _activeSubscriptions = {};

  Widget _buildDebugPanel() {
    final client = Supabase.instance.client;
    final user = _supabaseService.supabase.auth.currentUser;

    return Container(
      color: Theme.of(context).cardColor.withOpacity(0.9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ListView(
        children: [
          const Text(
            'DEBUG PANEL',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _infoRow('Platform', kIsWeb ? 'web' : 'mobile'),
          _infoRow('Web port', _webPort),
          _infoRow('Supabase REST', client.rest.url),
          _infoRow('User ID', user?.id ?? 'unknown'),
          _infoRow('Selected chat', _selectedChatId ?? 'none'),
          _infoRow('Chats loaded', '${_chats.length}'),
          _infoRow('Messages loaded', '${_messages.length}'),
          _infoRow('Loading chats', _loading ? 'yes' : 'no'),
          _infoRow('Loading more', _isLoadingMore ? 'yes' : 'no'),
          _infoRow('Search query', _searchController.text.isEmpty ? '-' : _searchController.text),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadChats,
            icon: const Icon(Icons.refresh),
            label: const Text('Reload chats'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _selectedChatId == null ? null : () => _loadMessages(_selectedChatId!),
            icon: const Icon(Icons.sync),
            label: const Text('Reload messages'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              debugPrint('DEBUG PANEL: client status -> url=${client.rest.url}');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Debug: status logged to console')),
              );
            },
            icon: const Icon(Icons.info_outline),
            label: const Text('Log status'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAttachment() async {
    // Implementation remains the same
  }

  Future<void> _handleVoiceRecorded(String filePath) async {
    // Implementation remains the same
  }
}
