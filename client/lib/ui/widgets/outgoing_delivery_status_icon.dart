import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class OutgoingDeliveryStatusIcon extends StatelessWidget {
  const OutgoingDeliveryStatusIcon({
    super.key,
    required this.status,
    this.onRetryNow,
    this.size = 16,
  });

  final String status;
  final VoidCallback? onRetryNow;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    switch (status) {
      case 'pending':
        return _PulsingIcon(
          icon: Icons.access_time,
          color: c.gray,
          size: size,
        );
      case 'delivered':
        return Icon(Icons.done_all, size: size, color: c.primary);
      case 'failed':
        final iconWidget = Icon(
          Icons.error_outline,
          size: size,
          color: c.error,
        );
        if (onRetryNow == null) return iconWidget;
        return GestureDetector(
          onTap: onRetryNow,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: iconWidget,
          ),
        );
      case 'sent':
      default:
        return Icon(Icons.done, size: size, color: c.gray);
    }
  }
}

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
        final opacity = 0.5 + 0.5 * (1 - (_controller.value - 0.5).abs() * 2);
        return Opacity(opacity: opacity, child: child);
      },
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}
