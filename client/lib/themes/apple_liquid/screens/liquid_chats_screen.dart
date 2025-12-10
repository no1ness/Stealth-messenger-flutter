import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
import 'package:intl/intl.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/glass_text_field.dart';
import '../widgets/glass_chat_bubble.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../components/glass_container.dart';

class LiquidChatsScreen extends StatefulWidget {
  final String? initialChatId;
  const LiquidChatsScreen({super.key, this.initialChatId});

  @override
  State<LiquidChatsScreen> createState() => _LiquidChatsScreenState();
}

class _LiquidChatsScreenState extends State<LiquidChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? _selectedChatId;
  final SupabaseService _supabaseService = SupabaseService();
  bool _loading = true;
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _messages = [];
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _supabaseService.unsubscribeFromMessages();
    _supabaseService.unsubscribeTyping();
    _supabaseService.unsubscribeCalls();
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _myUserId = await _supabaseService.getUserId();
    if (!mounted) return;
    await _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() => _loading = true);
    final rows = await _supabaseService.fetchChats();
    if (!mounted) return;
    
    final chats = <Map<String, dynamic>>[];
    final String? me = await _supabaseService.getUserId();
    final Set<String> allMemberIds = rows
        .expand((row) => (row['members'] as List<dynamic>? ?? []).cast<String>())
        .toSet();
    await _supabaseService.getNicknames(allMemberIds);
    
    for (final row in rows) {
      final List<dynamic> members = row['members'] ?? [];
      String title = 'Chat';
      
      if (members.length == 1) {
        title = (await _supabaseService.getUserNicknameById((members.first as String?) ?? '')) ?? 'Chat';
      } else if (members.length == 2) {
        final String? otherId = members.cast<String?>().firstWhere((m) => m != me, orElse: () => null);
        title = (await _supabaseService.getUserNicknameById(otherId ?? '')) ?? 'Chat';
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
          lastText = (last['ciphertext'] as String? ?? '').trim();
        }
      } catch (e) {
        debugPrint('Error processing message preview: $e');
      }
      
      int unread = 0;
      final lastSeen = await _supabaseService.getLastSeen(row['id'] as String) ?? 
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
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
    
    setState(() {
      _chats = chats;
      _loading = false;
    });
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chatDate = DateTime(dt.year, dt.month, dt.day);
    
    if (chatDate == today) {
      return DateFormat('HH:mm').format(dt);
    } else if (now.difference(chatDate).inDays < 7) {
      return DateFormat('EEE').format(dt);
    } else {
      return DateFormat('dd/MM/yy').format(dt);
    }
  }

  void _selectChat(String chatId) {
    setState(() {
      _selectedChatId = chatId;
    });
    _loadMessages(chatId);
  }

  Future<void> _loadMessages(String chatId) async {
    final messages = await _supabaseService.fetchMessages(chatId);
    if (!mounted) return;
    
    setState(() {
      _messages = messages.map((msg) {
        return {
          'id': msg['id'],
          'text': msg['ciphertext'],
          'isSent': msg['sender_id'] == _myUserId,
          'timestamp': _formatTimestamp(DateTime.parse(msg['created_at']).toLocal()),
        };
      }).toList();
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _selectedChatId == null) return;
    
    final text = _messageController.text.trim();
    _messageController.clear();
    
    await _supabaseService.sendMessage(
      chatId: _selectedChatId!,
      content: text,
      type: 'text',
    );
    await _loadMessages(_selectedChatId!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundPrimary,
              AppColors.backgroundSecondary,
              AppColors.backgroundPrimary,
            ],
          ),
        ),
        child: SafeArea(
          child: _selectedChatId == null ? _buildChatsList() : _buildChatView(),
        ),
      ),
    );
  }

  Widget _buildChatsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Messages',
                style: AppTypography.largeTitle.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassSearchField(
                controller: _searchController,
                hintText: 'Search',
                onChanged: (value) {
                  // Implement search
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _chats.isEmpty
                  ? Center(
                      child: Text(
                        'No chats yet',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      itemCount: _chats.length,
                      itemBuilder: (context, index) {
                        final chat = _chats[index];
                        return _buildChatListItem(chat);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildChatListItem(Map<String, dynamic> chat) {
    final unreadCount = int.tryParse(chat['unreadCount'] ?? '0') ?? 0;
    
    return GlassCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      onTap: () => _selectChat(chat['id']),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.liquidGradient1,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                chat['name'][0].toUpperCase(),
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      chat['name'],
                      style: AppTypography.headline.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      chat['timestamp'] ?? '',
                      style: AppTypography.caption1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat['lastMessage'] ?? 'No messages',
                        style: AppTypography.subheadline.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: AppColors.liquidGradient1,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unreadCount.toString(),
                          style: AppTypography.caption1.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatView() {
    final chatName = _chats.firstWhere(
      (c) => c['id'] == _selectedChatId,
      orElse: () => {'name': 'Chat'},
    )['name'];
    
    return Column(
      children: [
        GlassAppBar(
          title: chatName,
          showBackButton: true,
          onBackPressed: () {
            setState(() {
              _selectedChatId = null;
              _messages = [];
            });
          },
          actions: [
            IconButton(
              icon: const Icon(Icons.videocam, color: AppColors.systemBlue),
              onPressed: () {
                // Start video call
              },
            ),
            IconButton(
              icon: const Icon(Icons.call, color: AppColors.systemBlue),
              onPressed: () {
                // Start voice call
              },
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            reverse: true,
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[_messages.length - 1 - index];
              return GlassChatBubble(
                message: msg['text'],
                type: msg['isSent'] ? MessageType.sent : MessageType.received,
                timestamp: msg['timestamp'],
              );
            },
          ),
        ),
        GlassChatInput(
          controller: _messageController,
          onSend: _sendMessage,
          onAttachment: () {
            // Handle attachment
          },
          onVoice: () {
            // Handle voice message
          },
        ),
      ],
    );
  }
}
