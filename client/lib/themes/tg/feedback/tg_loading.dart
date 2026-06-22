import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_colors.dart';

class TgLoading {
  static Widget spinner({double size = 24, Color? color}) {
    return _TgLoadingSpinner(size: size, color: color);
  }

  static Widget page() {
    return const Center(child: CircularProgressIndicator());
  }
}

class _TgLoadingSpinner extends StatelessWidget {
  final double size;
  final Color? color;

  const _TgLoadingSpinner({required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: color ?? c.primary,
      ),
    );
  }
}
