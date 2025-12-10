import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../constants/glass_styles.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final bool isLargeTitle;
  final double? elevation;

  const GlassAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.showBackButton = false,
    this.onBackPressed,
    this.isLargeTitle = false,
    this.elevation,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        isLargeTitle ? AppSpacing.navBarLargeHeight : AppSpacing.navBarHeight,
      );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.darkGray2.withOpacity(0.8),
            border: const Border(
              bottom: BorderSide(
                color: AppColors.separator,
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Container(
              height: isLargeTitle
                  ? AppSpacing.navBarLargeHeight
                  : AppSpacing.navBarHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
              child: isLargeTitle ? _buildLargeTitleBar() : _buildStandardBar(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardBar() {
    return Row(
      children: [
        if (showBackButton || leading != null)
          leading ??
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: AppColors.systemBlue,
                  size: AppSpacing.iconMd,
                ),
                onPressed: onBackPressed,
              ),
        Expanded(
          child: Center(
            child: titleWidget ??
                Text(
                  title ?? '',
                  style: AppTypography.headline.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
          ),
        ),
        if (actions != null) ...actions!,
        if (actions == null) const SizedBox(width: AppSpacing.huge),
      ],
    );
  }

  Widget _buildLargeTitleBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (actions != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions!,
          ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: titleWidget ??
              Text(
                title ?? '',
                style: AppTypography.largeTitle.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
        ),
      ],
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
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.darkGray2.withOpacity(0.8),
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
    );
  }
}
