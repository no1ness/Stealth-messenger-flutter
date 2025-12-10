import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:stealth/supabase_service.dart';
import 'package:stealth/ui/screens/chats_screen.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  bool _loading = true;
  List<Map<String, dynamic>> _contacts = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    setState(() => _loading = false); // Don't show loading
    _loadContacts(); // Load in background
  }

  Future<void> _loadContacts() async {
    debugPrint('DEBUG: _loadContacts() called');
    // Don't show loading spinner for cached data
    final rows = await _supabaseService.getContacts();
    debugPrint('DEBUG: getContacts() returned ${rows.length} contacts');
    if (!mounted) return;

    // Show data immediately when available
    if (rows.isNotEmpty) {
      setState(() => _loading = false);
    }

    setState(() {
      _contacts = rows.cast<Map<String, dynamic>>();
      _loading = false;
    });
    debugPrint('DEBUG: _contacts updated to ${_contacts.length} contacts');
  }

  Future<void> _addDefaultContacts() async {
    try {
      // These methods are removed as they are not part of the core functionality
      // and were causing issues with the original schema.
      await _loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Контакты по умолчанию добавлены'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка добавления контактов: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _startCallWithContact(Map<String, dynamic> contact) async {
    // WebRTC calls are now supported on web platform
    
    final otherUserId = (contact['user_id'] as String?) ?? '';
    if (otherUserId.isEmpty) return;
    
    // Check if trying to call yourself
    final currentUserId = await _supabaseService.getUserId();
    if (currentUserId != null && otherUserId == currentUserId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нельзя звонить самому себе'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    final chatId = await _supabaseService.findOrCreatePrivateChatWith(otherUserId);
    if (!mounted || chatId == null) return;
    // Calling feature is temporarily disabled.
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebRTCCallScreen(
          peerName: (contact['name'] as String?) ?? 'Звонок',
          chatId: chatId,
          isCaller: true,
        ),
      ),
    );
  }

  void _showDeleteContactDialog(String userId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить контакт?'),
        content: Text('Удалить контакт "$name"?\n\nВсе чаты и сообщения с этим контактом будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // Сохраняем ScaffoldMessenger ДО async операций
              final messenger = ScaffoldMessenger.of(context);
              
              // Показываем индикатор загрузки
              if (mounted) {
                setState(() => _loading = true);
              }
              
              try {
                debugPrint('DEBUG: Starting contact deletion for userId: $userId, name: $name');
                debugPrint('DEBUG: Contacts before deletion: ${_contacts.length}');

                // Delete from database
                await _supabaseService.deleteContact(userId);

                // Remove from local list
                setState(() {
                  _contacts.removeWhere((c) => c['user_id'] == userId);
                  _loading = false; // Make sure loading is false
                });

                debugPrint('DEBUG: Contacts after deletion: ${_contacts.length}');

                if (!mounted) return;

                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Контакт "$name" удален'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                debugPrint('DEBUG: Error during contact deletion: $e');
                if (!mounted) return;

                setState(() => _loading = false);

                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Ошибка удаления: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showContactCard(Map<String, dynamic> contact) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Text(_initials(contact['name'] as String?))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((contact['name'] as String?) ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          Text('ID: ${(contact['user_id'] as String?) ?? ''}', style: TextStyle(color: Theme.of(context).hintColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        final chatId = await _supabaseService.findOrCreatePrivateChatWith((contact['user_id'] as String?) ?? '');
                        if (!mounted || chatId == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatsScreen(initialChatId: chatId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat),
                      label: const Text('Написать'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _contacts
        : _contacts.where((c) => (c['name'] as String? ?? '').toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _addDefaultContacts,
            tooltip: 'Добавить контакты по умолчанию',
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () async {
              final controller = TextEditingController();
              final userId = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Добавить контакт'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(hintText: 'Вставьте User ID'),
                      ),
                      const SizedBox(height: 16),
                      const Text('Или выберите контакт по умолчанию:'),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              controller.text = '11111111-1111-1111-1111-111111111111';
                            },
                            child: const Text('POCO'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              controller.text = '22222222-2222-2222-2222-222222222222';
                            },
                            child: const Text('GEEKOM'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Добавить')),
                  ],
                ),
              );
              if (userId == null || userId.isEmpty) return;
              
              try {
                // First, try to get the user's nickname
                final nickname = await _supabaseService.getNicknameForUser(userId);
                if (nickname == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Пользователь с таким ID не найден'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                  return;
                }
                
                // Add contact
                // Adding contacts is not supported in the simplified schema.
                
                // Create chat
                final chatId = await _supabaseService.findOrCreatePrivateChatWith(userId);
                if (!mounted || chatId == null) return;
                
                // Refresh contacts list
                await _loadContacts();
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Контакт $nickname добавлен'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatsScreen(initialChatId: chatId),
                      settings: const RouteSettings(name: '/chats'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка добавления контакта: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search contacts...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (_) => _loadContacts(),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No contacts yet.'))
                  : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final contact = filtered[index];
                      final bool isVerified = (contact['is_verified'] as bool?) ?? false;
                      final contactId = (contact['user_id'] as String?) ?? '';
                      final contactName = (contact['name'] as String?) ?? '';
                      
                      return Dismissible(
                        key: Key(contactId),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (direction) async {
                          _showDeleteContactDialog(contactId, contactName);
                          return false; // Не удаляем сразу, ждём подтверждения
                        },
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          leading: CircleAvatar(
                            child: Text(_initials(contact['name'] as String?)),
                          ),
                          title: Text(
                            (contact['name'] as String?) ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ID: ${(contact['user_id'] as String?) ?? ''}',
                              style: TextStyle(color: Theme.of(context).hintColor),
                            ),
                            if (isVerified)
                              Text(
                                'Verified',
                                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chat_bubble_outline),
                              onPressed: () async {
                                final chatId = await _supabaseService
                                    .findOrCreatePrivateChatWith((contact['user_id'] as String?) ?? '');
                                if (!mounted || chatId == null) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatsScreen(initialChatId: chatId),
                                    settings: const RouteSettings(name: '/chats'),
                                  ),
                                );
                              },
                            ),
                            // В веб версии показываем кнопку удаления вместо звонка
                            if (kIsWeb)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _showDeleteContactDialog(contactId, contactName),
                                tooltip: 'Удалить контакт',
                              ),
                          ],
                        ),
                        onTap: () async {
                          final chatId = await _supabaseService
                              .findOrCreatePrivateChatWith((contact['user_id'] as String?) ?? '');
                          if (!mounted || chatId == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatsScreen(initialChatId: chatId),
                              settings: const RouteSettings(name: '/chats'),
                            ),
                          );
                        },
                        onLongPress: () => _showDeleteContactDialog(contactId, contactName),
                        ),
                      );
                    },
                  ),
            ),
        ],
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r"\s+"));
    final a = parts.first.isNotEmpty ? parts.first[0] : '';
    final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (a + b).toUpperCase();
  }
}