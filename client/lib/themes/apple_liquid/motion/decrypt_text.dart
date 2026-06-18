import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:stealth/logging/logger.dart';

import '../constants/app_motion.dart';
import '../constants/app_typography.dart';

/// Animated "decrypting" reveal of a string.
///
/// Each character starts as a random character drawn from [alphabet]
/// and resolves to its target value at a staggered point along the
/// timeline. Reads as cipher-text decoding into the real string —
/// the signature first-impression moment for the Stealth wordmark
/// on the loading screen and any other "this is decrypting" UX beat.
///
/// **Defaults are cipher-flavoured:** hex characters (`0-9A-F`),
/// rendered in [AppTypography.title1] over [AppMotion.slow] (400 ms).
/// Override [alphabet] / [style] / [duration] for other contexts.
///
/// **Reduce-motion respect:** when `MediaQuery.disableAnimations` is
/// true the widget renders the final string immediately without
/// scrambling.
///
/// **Logged once on mount** so it's easy to verify the animation
/// fires on every cold launch.
class DecryptText extends StatefulWidget {
  const DecryptText(
    this.text, {
    super.key,
    this.duration = AppMotion.slow,
    this.style,
    this.alphabet,
    this.stagger,
    this.textAlign,
  });

  /// The target string to resolve to.
  final String text;

  /// Total animation duration. Per-character resolution happens at
  /// `progress >= staggerStart_i` where `staggerStart_i` is offset
  /// per character (left-to-right reveal).
  final Duration duration;

  /// Text style for the final string. Defaults to [AppTypography.title1].
  final TextStyle? style;

  /// Pool of scramble characters. Defaults to upper-case hex
  /// (`0-9A-F`) — fits the cryptographic-noir north star.
  final String? alphabet;

  /// Per-character stagger fraction of [duration]. If null, the
  /// effective stagger is `0.6 / max(1, text.length - 1)` so all
  /// characters resolve by 100% of the timeline.
  final double? stagger;

  final TextAlign? textAlign;

  @override
  State<DecryptText> createState() => _DecryptTextState();
}

class _DecryptTextState extends State<DecryptText>
    with SingleTickerProviderStateMixin {
  static const String _defaultAlphabet = '0123456789ABCDEF';

  late final AnimationController _controller;

  /// Stable per-frame scramble seed so each frame reuses the same
  /// random characters for any not-yet-resolved index (otherwise
  /// every frame would re-roll and look like a slot machine, which
  /// reads as noise rather than as decryption).
  ///
  /// The seed advances every ~50 ms so the scramble still feels alive.
  int _seedTick = 0;
  Duration _lastSeedAdvance = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.addListener(_onTick);
    Logger.debug('[ds:decrypt] mount text="${widget.text}" '
        'duration=${widget.duration.inMilliseconds}ms');
    // Defer to post-frame so MediaQuery is available for the
    // reduce-motion check.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _controller.value = 1;
        return;
      }
      _controller.forward();
    });
  }

  void _onTick() {
    final elapsed = widget.duration * _controller.value;
    if (elapsed - _lastSeedAdvance >= const Duration(milliseconds: 50)) {
      _lastSeedAdvance = elapsed;
      _seedTick++;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.text;
    final n = target.length;
    if (n == 0) return const SizedBox.shrink();

    final alphabet = widget.alphabet ?? _defaultAlphabet;
    final progress = _controller.value;
    // Per-character start offset on the timeline. Default stagger
    // spreads the START times across the first 60% of the timeline,
    // leaving the remaining 40% as each character's resolution window.
    final effectiveStagger =
        widget.stagger ?? (n <= 1 ? 0.0 : 0.6 / (n - 1));
    final lastStart = (n - 1) * effectiveStagger;
    // Window during which a single character monotonically settles
    // from "fully scrambled" to "fully resolved". Clamp so very long
    // strings still get a visible per-character animation rather than
    // collapsing to instant snap.
    final window = (1.0 - lastStart).clamp(0.05, 1.0);

    final rng = math.Random(_seedTick * 1103515245 ^ 0x55AA);
    final buf = StringBuffer();
    for (var i = 0; i < n; i++) {
      final resolveAt = i * effectiveStagger;

      if (progress >= resolveAt + window) {
        // Past full-resolution mark — emit final character.
        buf.write(target[i]);
        continue;
      }
      if (progress >= resolveAt) {
        // Inside resolution window. `localProgress` runs 0 → 1 across
        // the window; scrambleChance falls from 1 to 0 linearly so
        // characters monotonically settle from scramble → target.
        // Using a probability (rather than a hard switch) keeps the
        // reveal feeling alive instead of step-wise.
        final localProgress = (progress - resolveAt) / window;
        final scrambleChance = (1.0 - localProgress).clamp(0.0, 1.0);
        if (rng.nextDouble() > scrambleChance) {
          buf.write(target[i]);
        } else {
          buf.write(alphabet[rng.nextInt(alphabet.length)]);
        }
        continue;
      }
      // Not yet started: pure scramble. Spaces in the target stay as
      // spaces — looks more natural than scrambled whitespace.
      if (target[i] == ' ') {
        buf.write(' ');
      } else {
        buf.write(alphabet[rng.nextInt(alphabet.length)]);
      }
    }

    return Text(
      buf.toString(),
      textAlign: widget.textAlign,
      style: widget.style ?? AppTypography.title1,
    );
  }
}
