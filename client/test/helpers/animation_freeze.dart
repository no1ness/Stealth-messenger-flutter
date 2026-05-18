import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump a widget for a golden test without deadlocking on continuous
/// animations.
///
/// The codebase has several widgets that run a permanent
/// `AnimationController` loop (`StealthAnimatedBackground`, the
/// `GlassContainer` press animation, `GlassChatBubble` `AnimatedSize`,
/// `StaggeredListView` per-item entrance, `StealthSkeletonTile`
/// shimmer). Calling `tester.pumpAndSettle()` on a tree containing
/// any of them hangs the test runner — `pumpAndSettle` waits for the
/// scheduler to be idle, which never happens.
///
/// This helper does two things:
///
/// 1. Wraps the widget in `MediaQuery(disableAnimations: true)` so
///    well-behaved animation widgets (those that read the flag) skip
///    their entrance animation.
/// 2. Uses `pumpFrames` with a small fixed budget instead of
///    `pumpAndSettle`. After 100 ms of simulated time the tree has
///    settled enough for golden capture; any animation still running
///    is recorded at a deterministic frame.
///
/// Every golden test added under `client/test/golden/` should use
/// `pumpForGolden` rather than `pumpAndSettle`.
Future<void> pumpForGolden(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: widget,
    ),
  );
  await tester.pumpFrames(widget, const Duration(milliseconds: 100));
}
