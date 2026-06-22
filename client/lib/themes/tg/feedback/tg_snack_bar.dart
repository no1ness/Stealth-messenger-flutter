import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';

class TgSnackBar {
  static void show(BuildContext context, String message, {bool isError = false}) {
    final c = TgThemeColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 15, color: Colors.white)),
        backgroundColor: isError ? c.error : c.toastBackground,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
