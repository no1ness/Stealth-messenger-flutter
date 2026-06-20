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
    return child;
  }
}
