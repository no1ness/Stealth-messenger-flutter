import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

class TgSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final int? count;

  const TgSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(TgSpacing.screenEdge, TgSpacing.md, TgSpacing.screenEdge, TgSpacing.xs),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 2, color: c.text, height: 1.0),
          ),
          if (count != null) ...[
            const SizedBox(width: TgSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.primaryOpacity,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primary.withValues(alpha: 0.9), height: 1.2),
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
