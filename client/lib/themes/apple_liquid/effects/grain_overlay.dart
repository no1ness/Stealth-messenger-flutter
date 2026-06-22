import 'package:flutter/material.dart';

class GrainOverlay extends StatelessWidget {
  const GrainOverlay({
    super.key,
    required this.child,
    this.opacity = 0.03,
    this.force = false,
  });

  final Widget child;
  final double opacity;
  final bool force;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
