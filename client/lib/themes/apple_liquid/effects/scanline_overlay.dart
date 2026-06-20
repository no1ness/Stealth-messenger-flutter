import 'package:flutter/material.dart';

class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.force = false,
  });

  final Widget child;
  final double intensity;
  final bool force;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
