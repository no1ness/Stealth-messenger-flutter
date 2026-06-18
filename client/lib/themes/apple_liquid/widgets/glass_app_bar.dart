import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBackButton;
  final VoidCallback? onBack;
  final bool isLargeTitle;
  final double? elevation;

  const GlassAppBar({
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
  Size get preferredSize => Size.fromHeight(
        isLargeTitle ? 72 : 56,
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glassUltraDark,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.glassLight.withValues(alpha: 0.1),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: isLargeTitle ? 72 : 56,
                child: isLargeTitle
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: DefaultTextStyle(
                            style: AppTypography.title1.copyWith(
                              color: Colors.white,
                            ),
                            child: titleWidget ??
                                Text(
                                  title ?? '',
                                ),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          if (showBackButton)
                            IconButton(
                              tooltip: 'Назад',
                              icon: const Icon(Icons.arrow_back_ios_new,
                                  size: 20),
                              color: AppColors.systemBlue,
                              onPressed:
                                  onBack ?? () => Navigator.of(context).pop(),
                            ),
                          if (leading != null && !showBackButton) leading!,
                          Expanded(
                            child: titleWidget ??
                                Text(
                                  title ?? '',
                                  style: AppTypography.headline.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                          ),
                          if (actions != null) ...actions!,
                          if (actions == null && showBackButton)
                            const SizedBox(width: 48),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassSliverAppBar extends StatelessWidget {
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

  const GlassSliverAppBar({
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
    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: pinned,
      floating: floating,
      leading: showBackButton || leading != null
          ? (leading ??
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: AppColors.systemBlue,
                ),
                onPressed: onBackPressed,
              ))
          : null,
      actions: actions,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRRect(
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.darkGray2.withValues(alpha: 0.8),
                border: const Border(
                  bottom: BorderSide(
                    color: AppColors.separator,
                    width: 0.5,
                  ),
                ),
              ),
              child: FlexibleSpaceBar(
                title: titleWidget ??
                    Text(
                      title ?? '',
                      style: AppTypography.headline.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                centerTitle: false,
                titlePadding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  bottom: AppSpacing.md,
                ),
                background: flexibleSpace,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
