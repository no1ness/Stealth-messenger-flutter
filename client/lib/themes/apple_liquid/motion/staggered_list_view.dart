import 'package:flutter/material.dart';
import 'package:stealth/logging/logger.dart';

import '../constants/app_motion.dart';

/// `ListView.builder` wrapper that fades+translates each item in
/// with a small stagger delay on first render.
///
/// Frontend-design north star: "one well-orchestrated page load
/// with staggered reveals creates more delight than scattered
/// micro-interactions". This is the one orchestrated reveal.
///
/// Rules:
///
/// - Each item is wrapped in a `RepaintBoundary` so the entrance
///   animation does not invalidate sibling items.
/// - After [maxStaggered] items the rest render without animation
///   (the choreography matters for the visible viewport — not for
///   item 47 in a long list).
/// - Respects `MediaQuery.disableAnimations`: with reduce-motion
///   on, items appear immediately.
/// - Stagger fires only on first render of a given key. Scrolling
///   does not re-trigger.
class StaggeredListView extends StatefulWidget {
  const StaggeredListView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.stagger = const Duration(milliseconds: 40),
    this.maxStaggered = 8,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.controller,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Duration stagger;
  final int maxStaggered;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final ScrollController? controller;

  @override
  State<StaggeredListView> createState() => _StaggeredListViewState();
}

class _StaggeredListViewState extends State<StaggeredListView> {
  /// Set on `initState` and never cleared — controls whether the
  /// stagger animation should run for a given index. After the
  /// first build it is replaced with an empty set so scrolling
  /// further into the list doesn't keep firing animations.
  late final DateTime _mountedAt;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    Logger.debug('[ds:stagger] mount itemCount=${widget.itemCount} '
        'stagger=${widget.stagger.inMilliseconds}ms max=${widget.maxStaggered}');
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ListView.builder(
      controller: widget.controller,
      padding: widget.padding,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        final child = RepaintBoundary(
          child: widget.itemBuilder(context, index),
        );
        if (reduceMotion || index >= widget.maxStaggered) {
          return child;
        }
        // Only animate items that are part of the initial reveal —
        // i.e. the screen mounted very recently. After ~1 second
        // we treat subsequent builds (e.g. setState refresh) as
        // non-animated to avoid stutter when the list grows.
        final age = DateTime.now().difference(_mountedAt);
        if (age > const Duration(seconds: 1)) {
          return child;
        }
        return _StaggeredEntry(
          delay: widget.stagger * index,
          child: child,
        );
      },
    );
  }
}

class _StaggeredEntry extends StatefulWidget {
  const _StaggeredEntry({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.normal,
    );
    final curve =
        CurvedAnimation(parent: _controller, curve: AppMotion.emphasized);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(curve);
    Future<void>.delayed(widget.delay, () {
      if (!mounted) {
        return;
      }
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}
