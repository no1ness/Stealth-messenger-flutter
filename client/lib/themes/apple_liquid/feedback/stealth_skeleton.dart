import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_motion.dart';
import '../constants/app_spacing.dart';

/// Shimmering skeleton placeholder used while a real list row is
/// loading.
///
/// Replaces bare `CircularProgressIndicator()` in chats / contacts /
/// profile screens. A page of skeleton tiles communicates "we're
/// loading the SHAPE of the data, here's what it'll look like"
/// instead of "we have no idea, please wait".
///
/// Animation respects `MediaQuery.disableAnimations` — for reduce-
/// motion users the tile renders as a static muted bar.
///
/// Wrapped in `RepaintBoundary` so the shimmer redraws independently
/// of the surrounding list.
class StealthSkeletonTile extends StatefulWidget {
  const StealthSkeletonTile({
    super.key,
    this.height = 64,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenEdge,
      vertical: AppSpacing.xs,
    ),
  });

  final double height;
  final EdgeInsetsGeometry padding;

  @override
  State<StealthSkeletonTile> createState() => _StealthSkeletonTileState();
}

class _StealthSkeletonTileState extends State<StealthSkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnim =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: widget.padding,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = disableAnim ? 0.5 : _controller.value;
              final alpha = 0.10 + 0.12 * t;
              return Container(
                height: widget.height,
                color: AppColors.surfaceMuted.withValues(alpha: alpha),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Convenience: vertical list of [count] skeleton tiles, used as the
/// loading state for chats / contacts screens.
class StealthSkeletonList extends StatelessWidget {
  const StealthSkeletonList({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: count,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemBuilder: (_, __) => const StealthSkeletonTile(),
    );
  }
}
