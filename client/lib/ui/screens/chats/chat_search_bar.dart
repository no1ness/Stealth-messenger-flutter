import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';



class ChatSearchBar extends StatefulWidget {
  const ChatSearchBar({
    super.key,
    required this.controller,
    required this.onSearchChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSearchChanged;

  @override
  State<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<ChatSearchBar> {
  Timer? _debounce;

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () {
        if (mounted) {
          widget.onSearchChanged();
        }
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return GlassSearchField(
      controller: widget.controller,
      hintText: 'Поиск чатов',
      onChanged: _onChanged,
    );
  }
}
