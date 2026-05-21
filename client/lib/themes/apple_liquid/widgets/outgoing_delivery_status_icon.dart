import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// 16-px lifecycle indicator for OUTGOING 1:1 messages only.
///
/// Render scope (locked in by task #10 of the post-PocketBase hardening
/// plan): incoming messages have no icon; group-chat messages have no
/// icon (groups don't go over P2P today — see task #8 / #9 refinements).
/// Caller is responsible for that gating — this widget renders whatever
/// status it's given.
///
/// Tap action is only meaningful for `failed` — `onRetryNow` may be
/// `null` for non-failed states. The widget itself doesn't decide;
/// it just attaches a [GestureDetector] over the icon when failed.
class OutgoingDeliveryStatusIcon extends StatelessWidget {
  const OutgoingDeliveryStatusIcon({
    super.key,
    required this.status,
    this.onRetryNow,
    this.size = 16,
  });

  /// Status string straight from `deliveryStatus` IDB field. Unknown
  /// values render as `sent` (legacy rows from before task #8 schema).
  final String status;

  /// Tap callback for the `failed` state. Null = no tap response.
  final VoidCallback? onRetryNow;

  final double size;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'pending':
        return _PulsingIcon(
          icon: Icons.access_time,
          color: AppColors.systemGray2,
          size: size,
        );
      case 'delivered':
        return Icon(Icons.done_all, size: size, color: AppColors.systemBlue);
      case 'failed':
        final iconWidget = Icon(
          Icons.error_outline,
          size: size,
          color: AppColors.systemRed,
        );
        if (onRetryNow == null) return iconWidget;
        return GestureDetector(
          onTap: onRetryNow,
          // Make the hit target a touch larger than the visible icon.
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: iconWidget,
          ),
        );
      case 'sent':
      default:
        return Icon(Icons.done, size: size, color: AppColors.systemGray2);
    }
  }
}

/// Minimal pulsing-opacity wrapper for the `pending` state. Keeps the
/// state visually distinct from `sent` without adding heavy animation.
class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 0.5 → 1.0 → 0.5 opacity loop.
        final opacity = 0.5 + 0.5 * (1 - (_controller.value - 0.5).abs() * 2);
        return Opacity(opacity: opacity, child: child);
      },
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}
