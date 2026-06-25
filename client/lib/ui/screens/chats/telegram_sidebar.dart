import 'package:flutter/material.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

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

class _TelegramSidebarState extends State<TelegramSidebar> {
  TgThemeColors get c => TgThemeColors.of(context);
  final TextEditingController _searchController = TextEditingController();
  final LocalAppService _appService = LocalAppService();

  List<Map<String, dynamic>> _filteredChats = [];

  @override
  void initState() {
    super.initState();
    _filteredChats = widget.chats;
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
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredChats = widget.chats;
    } else {
      _filteredChats = widget.chats.where((chat) {
        final name = (chat['name'] as String? ?? '').toLowerCase();
        return name.contains(query);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      decoration: BoxDecoration(
        color: c.backgroundSecondary,
        border: Border(
          right: BorderSide(
            color: c.dividers,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          _buildTabBar(),
          Expanded(
            child: _buildChatList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: TgSpacing.sm),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 24),
            color: c.textSecondary,
            onPressed: () {
              // TODO: Open hamburger menu drawer
            },
          ),
          const SizedBox(width: TgSpacing.xs),
          Expanded(
            child: Text(
              'Stealth',
              style: TgTypography.title1.copyWith(
                color: c.text,
                fontSize: 20,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_square, size: 22),
            color: c.textSecondary,
            onPressed: () {
              // TODO: New message
            },
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
      child: Row(
        children: [
          _buildFilterChip('Все'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: c.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
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
