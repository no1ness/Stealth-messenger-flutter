import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, TargetPlatform;

import '../constants/app_motion.dart';

/// Stealth-branded page route.
///
/// Variants:
///
/// - `GlassPageRoute(builder: ...)` — slide-from-right + fade-in,
///   the default for forward navigation. On iOS the underlying
///   `CupertinoPageRoute` is reused so the swipe-back gesture
///   continues to work; on Android/web a `PageRouteBuilder` with
///   matching duration/curve is used instead.
/// - `GlassPageRoute.modal(builder: ...)` — slide-from-bottom +
///   fade-in, the "this screen is taking over" variant. Use for
///   the WebRTC call screen and any other priority modal.
abstract class GlassPageRoute<T> extends PageRoute<T> {
  /// Factory selecting the appropriate platform-aware implementation.
  factory GlassPageRoute({
    required WidgetBuilder builder,
    String? name,
    RouteSettings? settings,
  }) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _GlassCupertinoPageRoute<T>(
        builder: builder,
        settings: settings ?? RouteSettings(name: name),
      );
    }
    return _GlassSlidePageRoute<T>(
      builder: builder,
      modal: false,
      settings: settings ?? RouteSettings(name: name),
    );
  }

  /// Modal slide-up variant. Used for priority screens (call screen).
  factory GlassPageRoute.modal({
    required WidgetBuilder builder,
    String? name,
    RouteSettings? settings,
  }) {
    return _GlassSlidePageRoute<T>(
      builder: builder,
      modal: true,
      settings: settings ?? RouteSettings(name: name),
    );
  }

}

class _GlassCupertinoPageRoute<T> extends CupertinoPageRoute<T>
    implements GlassPageRoute<T> {
  _GlassCupertinoPageRoute({required super.builder, super.settings}) {
    debugPrint('[ds:route] push (iOS cupertino) name=${settings.name ?? "<unnamed>"}');
  }
}

class _GlassSlidePageRoute<T> extends PageRoute<T>
    implements GlassPageRoute<T> {
  _GlassSlidePageRoute({
    required this.builder,
    required this.modal,
    super.settings,
  }) {
    debugPrint(
      '[ds:route] push (slide ${modal ? "modal" : "forward"}) '
      'name=${settings.name ?? "<unnamed>"}',
    );
  }

  final WidgetBuilder builder;
  final bool modal;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => AppMotion.pageRoute;

  @override
  Duration get reverseTransitionDuration => AppMotion.pageRoute;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }
    final begin = modal ? const Offset(0, 1) : const Offset(1, 0);
    final tween = Tween<Offset>(begin: begin, end: Offset.zero)
        .chain(CurveTween(curve: AppMotion.emphasized));
    return SlideTransition(
      position: animation.drive(tween),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}
