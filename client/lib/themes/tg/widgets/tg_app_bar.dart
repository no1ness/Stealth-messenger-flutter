import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';
import 'package:stealth/themes/tg/tg_spacing.dart';

class TgAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBackButton;
  final VoidCallback? onBack;
  final bool isLargeTitle;
  final double? elevation;

  const TgAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.showBackButton = false,
    this.onBack,
    this.isLargeTitle = false,
    this.elevation,
  });

  @override
  Size get preferredSize => Size.fromHeight(isLargeTitle ? 72 : 56);

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.backgroundSecondary,
        border: Border(
          bottom: BorderSide(color: c.dividers, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: isLargeTitle ? 72 : 56,
          child: isLargeTitle
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: DefaultTextStyle(
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2, color: Colors.white),
                            child: titleWidget ?? Text(title ?? ''),
                          ),
                        ),
                      ),
                      if (actions != null) ...actions!,
                    ],
                  ),
                )
              : Row(
                  children: [
                    if (showBackButton)
                      IconButton(
                        tooltip: 'Назад',
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        color: c.primary,
                        onPressed: onBack ?? () => Navigator.of(context).pop(),
                      ),
                    if (leading != null && !showBackButton) leading!,
                    Expanded(
                      child: titleWidget ??
                          Text(
                            title ?? '',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
                            textAlign: TextAlign.center,
                          ),
                    ),
                    if (actions != null) ...actions!,
                    if (actions == null && showBackButton) const SizedBox(width: 48),
                  ],
                ),
        ),
      ),
    );
  }
}

class TgSliverAppBar extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final double expandedHeight;
  final Widget? flexibleSpace;
  final bool pinned;
  final bool floating;

  const TgSliverAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.showBackButton = false,
    this.onBackPressed,
    this.expandedHeight = 120.0,
    this.flexibleSpace,
    this.pinned = true,
    this.floating = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: pinned,
      floating: floating,
      leading: showBackButton || leading != null
          ? (leading ?? IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              color: c.primary,
              onPressed: onBackPressed,
            ))
          : null,
      actions: actions,
      backgroundColor: c.backgroundSecondary,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        title: titleWidget ??
            Text(title ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: TgSpacing.md, bottom: TgSpacing.md),
        background: flexibleSpace,
      ),
    );
  }
}
