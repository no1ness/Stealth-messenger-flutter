import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';

class TgDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'OK',
    String cancelText = 'Отмена',
    bool isDestructive = false,
  }) {
    final c = TgThemeColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
        content: Text(message, style: TextStyle(fontSize: 15, color: c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelText, style: TextStyle(color: c.textSecondary, fontSize: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmText,
              style: TextStyle(
                color: isDestructive ? c.error : c.primary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
