import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

class TgContactTile extends StatelessWidget {
  final String name;
  final String? status;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? avatarUrl;

  const TgContactTile({
    super.key,
    required this.name,
    this.status,
    this.onTap,
    this.trailing,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Card(
      color: c.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: TgSpacing.screenEdge, vertical: TgSpacing.xxs),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgSpacing.radiusXl)),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgSpacing.radiusXl)),
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: _avatarGradient(name),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(name),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        title: Text(
          name,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text, height: 1.4),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: status != null
            ? Text(
                status!,
                style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.35),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: trailing,
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

  static String _initials(String value) {
    if (value.trim().isEmpty) return '?';
    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}
