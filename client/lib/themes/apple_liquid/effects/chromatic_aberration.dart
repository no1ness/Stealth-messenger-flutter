import 'package:flutter/material.dart';

class ChromaticAberration extends StatelessWidget {
  const ChromaticAberration({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.force = false,
    this.ghostBuilder,
  });

  final Widget child;
  final double intensity;
  final bool force;
  final WidgetBuilder? ghostBuilder;

  @override
  Widget build(BuildContext context) {
    if (intensity == 0) return child;

    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    if (!isDark && !force) return child;

    final ghost = ghostBuilder != null ? ghostBuilder!(context) : child;

    return RepaintBoundary(
      child: Stack(
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.matrix([
              1, 0, 0, 0, 0,
              0, 0, 0, 0, 0,
              0, 0, 0, 0, 0,
              0, 0, 0, intensity * 0.5, 0,
            ]),
            child: Transform.translate(
              offset: Offset(-intensity * 3, 0),
              child: ghost,
            ),
          ),
          ColorFiltered(
            colorFilter: ColorFilter.matrix([
              0, 0, 0, 0, 0,
              0, 1, 0, 0, 0,
              0, 0, 1, 0, 0,
              0, 0, 0, intensity * 0.5, 0,
            ]),
            child: Transform.translate(
              offset: Offset(intensity * 3, 0),
              child: ghost,
            ),
          ),
          child,
        ],
      ),
    );
  }
}
