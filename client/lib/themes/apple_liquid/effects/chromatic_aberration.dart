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
/// **Performance.** When [intensity] > 0 the widget renders [child]
/// three times (baseline + two coloured ghosts). Keep it scoped to
/// small subtrees (a single input, a small badge) — do NOT wrap a
/// full screen. Wrapped in `RepaintBoundary` so the ghosts don't
/// invalidate sibling subtrees.
///
/// **Ghost-layer escape hatch.** Pass [ghostBuilder] to supply a
/// cheaper subtree for the two coloured ghost layers while keeping
/// the full [child] as the interactive baseline. On web, for example,
/// you can pass a lightweight border-only widget to avoid rendering
/// an expensive input subtree three times — see
/// `GlassTextField._GlassFieldGhost`. When [ghostBuilder] is null
/// (the default) the ghost layers fall back to [child] for backward
/// compatibility.
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

  /// Optional builder for the two coloured ghost layers.
  ///
  /// When non-null, each ghost layer calls [ghostBuilder] instead of
  /// rendering [child], saving [child] from being built three times.
  /// The interactive baseline always uses [child].
  ///
  /// Default: null (ghost layers use [child], preserving the original
  /// three-build behaviour).
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
    final ghost = ghostBuilder != null ? ghostBuilder!(context) : child;
    debugPrint(
      '[fx:aberration] mount brightness=$brightness dx=$dx ghostBuilder=${ghostBuilder != null}',
    );
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
