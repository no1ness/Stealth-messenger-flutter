import 'package:flutter/material.dart';

import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/tg/tg_colors.dart';

/// Renders a deterministic, ultra-faint hex fingerprint pattern behind
/// the empty-state icon — the kind of grid you'd see formatting a
/// 256-bit safety number in `00:11:22:33` groups. Atmospheric only;
/// `IgnorePointer` so it doesn't intercept the action button.
///
/// Theme-aware: dark mode only. In light mode the pattern would read
/// as visual noise against the near-white scaffold and break the
/// "accessibility / high contrast" intent — so we return `SizedBox`.
class _KeyFingerprintBackdrop extends StatelessWidget {
  const _KeyFingerprintBackdrop({required this.seed});

  /// Seed string — typically the empty-state `title`. Same seed →
  /// same fingerprint across rebuilds (stable for golden snapshots).
  final String seed;

  static const int _rows = 14;
  static const int _pairsPerRow = 8;

  /// Linear congruential generator with a stable seed derived from
  /// the input string. We deliberately avoid `dart:math.Random` so the
  /// output is fully deterministic across platforms.
  int _hash(String s) {
    var h = 0x811C9DC5;
    for (final code in s.codeUnits) {
      h = ((h ^ code) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  String _buildPattern() {
    final buf = StringBuffer();
    var state = _hash(seed);
    for (var r = 0; r < _rows; r++) {
      for (var p = 0; p < _pairsPerRow; p++) {
        state = (state * 1103515245 + 12345) & 0xFFFFFFFF;
        final pair = (state >> 16) & 0xFF;
        if (p > 0) buf.write(':');
        buf.write(pair.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
      if (r < _rows - 1) buf.write('\n');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    if (isLight) return const SizedBox.shrink();

    return IgnorePointer(
      child: Opacity(
        opacity: 0.035,
        child: Center(
          child: Text(
            _buildPattern(),
            textAlign: TextAlign.center,
            style: AppTypography.captionMono.copyWith(
              color: AppColors.textPrimary,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state widget for the Stealth design system.
///
/// Reads from [AppColors] (NOT `Theme.of(context).colorScheme`) so
/// it stays consistent with the rest of the app. Wraps the body in
/// a [GrainOverlay] — empty states feel atmospheric rather than
/// blank, in the spirit of the "refined crypto-noir" north star.
///
/// Two named constructors carry copy + iconography for the most
/// common slots; the unnamed constructor is for anything bespoke.
class StealthEmptyState extends StatelessWidget {
  const StealthEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  /// Chats list when the user has no conversations.
  const StealthEmptyState.chats({super.key, this.action})
      : icon = Icons.chat_bubble_outline,
        title = 'Нет переписок.',
        message =
            'Отправьте контактный бандл, чтобы начать. Stealth хранит молчание, пока вы не сделаете первый шаг.';

  /// Contacts list when the user has no contacts.
  const StealthEmptyState.contacts({super.key, this.action})
      : icon = Icons.person_add_alt_1_outlined,
        title = 'Ваша адресная книга приватна.',
        message =
            'Отсканируйте контактный бандл или вставьте приглашение. Ничто не покидает устройство без вашего ведома.';

  /// Calls list when there is no recent call activity.
  const StealthEmptyState.calls({super.key, this.action})
      : icon = Icons.call_outlined,
        title = 'Нет звонков.',
        message =
            'Исходящие или входящие — история начинается с первого вызова.';

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Logger.debug('[ds:empty-state] title=$title');
    return GrainOverlay(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _KeyFingerprintBackdrop(seed: title),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.textTertiary,
                        width: 1,
                      ),
                      color: AppColors.shadow,
                    ),
                    child: Icon(
                      icon,
                      size: 32,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    style: AppTypography.headline.copyWith(
                      color: AppColors.textOnGlass,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message!,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Legacy alias to keep existing import sites compiling during the
/// migration. New code should reach for [StealthEmptyState] directly.
///
/// The `type` parameter maps to the three named constructors;
/// unknown values fall back to the generic [StealthEmptyState].
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case 'chats':
        return const StealthEmptyState.chats();
      case 'contacts':
        return const StealthEmptyState.contacts();
      case 'calls':
        return const StealthEmptyState.calls();
      default:
        return const StealthEmptyState(
          icon: Icons.info_outline,
          title: 'Здесь ничего нет',
        );
    }
  }
}
