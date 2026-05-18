import 'package:flutter/material.dart';

import '../constants/app_effects.dart';

/// Signature chromatic-aberration overlay.
///
/// Renders [child] with two thin colored ghosts offset on the X axis
/// (one red ghost shifted left, one cyan ghost shifted right), giving
/// the subtle "RGB split" focus-cue look used in cinematic UI
/// (Mr. Robot, Cyberpunk 2077 HUD, Linear's "Insights" hover state).
///
/// Use it as a focus cue — wrap a `TextField`, an action button, or
/// the in-call HUD's encrypted badge in [ChromaticAberration] and
/// drive [intensity] from a focus-aware [AnimationController]. At
/// rest pass `intensity: 0` (which short-circuits to just [child]).
///
/// **Theme-aware gating.** In [Brightness.light] the overlay returns
/// [child] unchanged — same dual-identity contract as
/// `ScanlineOverlay` / `GrainOverlay`. Pass `force: true` to bypass
/// the gate (tests only).
///
/// **Performance.** When [intensity] > 0 the widget renders the
/// ghost subtree twice (red + cyan) plus the baseline [child]. By
/// default ghosts reuse [child], so an expensive subtree (e.g.
/// `BackdropFilter`) is paid for three times per frame during the
/// pulse. Pass [ghostBuilder] to substitute a cheaper representation
/// for the ghost layers — the canonical escape hatch on Flutter web
/// where `BackdropFilter` is dramatically more expensive than on
/// native Skia. Wrapped in `RepaintBoundary` so the ghosts don't
/// invalidate sibling subtrees.
class ChromaticAberration extends StatelessWidget {
  const ChromaticAberration({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.force = false,
    this.ghostBuilder,
  });

  final Widget child;

  /// 0 → no effect (returns [child]); 1 → full
  /// [AppEffects.aberrationDxPx] horizontal split. Values > 1 are
  /// allowed and amplify the offset — useful for entrance pulses.
  final double intensity;

  /// Test-only escape hatch for the dark-mode-only gate.
  final bool force;

  /// Optional builder for the red + cyan ghost layers. When `null`
  /// the ghosts reuse [child] (richest visual, full subtree cost).
  /// When non-null the builder is invoked twice (once per ghost) and
  /// its output is wrapped in the same `ColorFiltered + Transform +
  /// Opacity` chain — the interactive baseline on top is always
  /// [child], so a cheap [ghostBuilder] does not affect input
  /// handling or accessibility.
  final WidgetBuilder? ghostBuilder;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (intensity <= 0 || (brightness == Brightness.light && !force)) {
      if (brightness == Brightness.light) {
        debugPrint('[fx:aberration] gated-out brightness=light');
      }
      return child;
    }
    final dx = AppEffects.aberrationDxPx * intensity;
    debugPrint(
      '[fx:aberration] mount brightness=$brightness dx=$dx '
      'ghostBuilder=${ghostBuilder != null}',
    );
    final ghost = ghostBuilder?.call(context) ?? child;
    return RepaintBoundary(
      child: Stack(
        children: [
          // Red ghost shifted left.
          Positioned.fill(
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(-dx, 0),
                child: Opacity(
                  opacity: 0.45,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color(0xFFFF1A1A),
                      BlendMode.srcATop,
                    ),
                    child: ghost,
                  ),
                ),
              ),
            ),
          ),
          // Cyan ghost shifted right.
          Positioned.fill(
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: Opacity(
                  opacity: 0.45,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF1AFFFF),
                      BlendMode.srcATop,
                    ),
                    child: ghost,
                  ),
                ),
              ),
            ),
          ),
          // Baseline: the real, interactive child sits on top.
          child,
        ],
      ),
    );
  }
}
