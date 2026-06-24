import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:stealth/services/user_directory/presence_service.dart';
import 'package:stealth/services/user_directory/user_directory_service.dart';

/// Telegram-style sidebar: search + tabs + chat/contact list.
///
/// On desktop, this replaces the old 3-column layout's left panel.
/// Auto-loads contacts from PocketBase user_profiles.
class TelegramSidebar extends StatefulWidget {
  const TelegramSidebar({
    super.key,
    required this.chats,
    required this.selectedChatId,
    required this.onChatSelected,
    required this.onContactSelected,
    required this.loading,
  });

  final List<Map<String, dynamic>> chats;
  final String? selectedChatId;
  final void Function(String chatId) onChatSelected;
  final void Function(Map<String, dynamic> contact) onContactSelected;
  final bool loading;

  @override
  State<TelegramSidebar> createState() => _TelegramSidebarState();
}

class _TelegramSidebarState extends State<TelegramSidebar>
    with SingleTickerProviderStateMixin {
  TgThemeColors get c => TgThemeColors.of(context);
  final TextEditingController _searchController = TextEditingController();
  final LocalAppService _appService = LocalAppService();
  late TabController _tabController;

  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filteredChats = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _loadingContacts = true;
  StreamSubscription<Map<String, dynamic>>? _presenceSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _filteredChats = widget.chats;
    _loadContacts();
    _subscribeToPresence();
  }

  @override
  void didUpdateWidget(covariant TelegramSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chats != widget.chats) {
      _applyFilter();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _presenceSub?.cancel();
    super.dispose();
  }

  void _subscribeToPresence() {
    _presenceSub?.cancel();
    _presenceSub = PresenceService().onPresenceChange.listen((profile) {
      final userId = profile['userId'] as String?;
      if (userId == null || !mounted) return;
      setState(() {
        final idx = _contacts.indexWhere(
          (c) => (c['user_id'] ?? c['contact_user_id']) == userId,
        );
        if (idx >= 0) {
          _contacts[idx]['isOnline'] = profile['isOnline'];
          _contacts[idx]['lastSeen'] = profile['lastSeen'];
        }
      });
    });
  }

  Future<void> _loadContacts() async {
    if (!mounted) return;
    setState(() => _loadingContacts = true);

    try {
      final directoryProfiles = UserDirectoryService().getCachedProfiles();
      final localContacts = await _appService.getContacts();
      final me = await _appService.getUserId();

      final merged = <String, Map<String, dynamic>>{};

      for (final contact in localContacts.cast<Map<String, dynamic>>()) {
        final userId =
            (contact['user_id'] ?? contact['contact_user_id'])?.toString() ?? '';
        if (userId.isNotEmpty && userId != me) {
          final profile = directoryProfiles
              .where((p) => p['userId'] == userId)
              .firstOrNull;
          if (profile != null) {
            contact['isOnline'] = profile['isOnline'] ?? false;
            contact['lastSeen'] = profile['lastSeen'];
          }
          merged[userId] = contact;
        }
      }

      for (final profile in directoryProfiles) {
        final userId = profile['userId']?.toString() ?? '';
        if (userId.isNotEmpty && userId != me && !merged.containsKey(userId)) {
          merged[userId] = {
            'user_id': userId,
            'nickname': profile['nickname'] ?? userId,
            'name': profile['nickname'] ?? userId,
            'isOnline': profile['isOnline'] ?? false,
            'lastSeen': profile['lastSeen'],
          };
        }
      }

      if (mounted) {
        setState(() {
          _contacts = merged.values.toList();
          _loadingContacts = false;
        });
        _applyFilter();
      }
    } catch (e) {
      Logger.warn('[TelegramSidebar] failed to load contacts', extras: {'error': '$e'});
      if (mounted) {
        setState(() => _loadingContacts = false);
      }
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredChats = widget.chats;
      _filteredContacts = _contacts;
    } else {
      _filteredChats = widget.chats.where((chat) {
        final name = (chat['name'] as String? ?? '').toLowerCase();
        return name.contains(query);
      }).toList();
      _filteredContacts = _contacts.where((contact) {
        final name = (contact['nickname'] ?? contact['name'] ?? '').toString().toLowerCase();
        return name.contains(query);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: c.dividers,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildSearchBar(),
          _buildTabBar(),
          Expanded(
            child: _tabController.index == 0
                ? _buildChatList()
                : _buildContactList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        TgSpacing.sm,
        TgSpacing.sm,
        TgSpacing.sm,
        TgSpacing.xs,
      ),
      child: TgSearchField(
        controller: _searchController,
        hintText: 'Поиск',
        onChanged: (_) {
          setState(() => _applyFilter());
        },
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 40,
      margin: EdgeInsets.symmetric(horizontal: TgSpacing.sm),
      child: TabBar(
        controller: _tabController,
        onTap: (_) => setState(() {}),
        labelColor: c.primary,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TgTypography.subheadlineEmphasis,
        unselectedLabelStyle: TgTypography.subheadline,
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'Чаты'),
          Tab(text: 'Контакты'),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (widget.loading) {
      return Center(
        child: CircularProgressIndicator(
          color: c.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (_filteredChats.isEmpty) {
      return Center(
        child: Text(
          'Нет чатов',
          style: TgTypography.subheadline.copyWith(
            color: c.textSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: TgSpacing.xs),
      itemCount: _filteredChats.length,
      itemBuilder: (context, index) {
        final chat = _filteredChats[index];
        final isSelected = chat['id'] == widget.selectedChatId;
        return TgChatTile(
          chat: chat,
          isSelected: isSelected,
          onTap: () => widget.onChatSelected(chat['id'] as String),
        );
      },
    );
  }

  Widget _buildContactList() {
    if (_loadingContacts) {
      return Center(
        child: CircularProgressIndicator(
          color: c.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (_filteredContacts.isEmpty) {
      return Center(
        child: Text(
          'Нет контактов',
          style: TgTypography.subheadline.copyWith(
            color: c.textSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: TgSpacing.xs),
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        return _buildTgContactTile(contact);
      },
    );
  }

  Widget _buildTgContactTile(Map<String, dynamic> contact) {
    final name = (contact['nickname'] ?? contact['name'] ?? 'Контакт').toString();
    final isOnline = contact['isOnline'] as bool? ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onContactSelected(contact),
        borderRadius: BorderRadius.circular(TgSpacing.radiusMd),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: TgSpacing.sm,
            vertical: TgSpacing.xs,
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: _avatarGradient(name),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(name),
                      style: TgTypography.calloutEmphasis.copyWith(
                        color: c.text,
                      ),
                    ),
                  ),
                  if (isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.green,
                          border: Border.fromBorderSide(
                            BorderSide(color: c.background, width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: TgSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TgTypography.bodyEmphasis.copyWith(
                        color: c.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOnline ? 'в сети' : 'не в сети',
                      style: TgTypography.caption1.copyWith(
                        color: isOnline
                            ? c.green
                            : c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Gradient _avatarGradient(String name) {
    final hash = name.hashCode;
    final hue1 = (hash.abs() % 360).toDouble();
    final hue2 = ((hash.abs() * 7 + 120) % 360).toDouble();
    return LinearGradient(
      colors: [
        HSLColor.fromAHSL(1, hue1, 0.7, 0.4).toColor(),
        HSLColor.fromAHSL(1, hue2, 0.7, 0.3).toColor(),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  static String _initials(String? value) {
    if (value == null || value.trim().isEmpty) return '?';
    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
