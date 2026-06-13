import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_elevation.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../effects/scanline_overlay.dart';
import 'stealth_snack_bar.dart';

/// Importance level. [high] adds a `ScanlineOverlay` so the dialog
/// visually distinguishes itself from routine info dialogs — used
/// for destructive ops (logout, delete-all, rotate-identity-key,
/// factory-reset).
enum DialogImportance { normal, high }

/// Visual / behavioural variant for a dialog action button.
enum StealthDialogActionVariant { primary, secondary, destructive }

/// Single button in the dialog's action row.
///
/// `destructive` actions go through a 2-tap "armed" gate by default
/// (first tap fires a snackbar asking for confirmation; second tap
/// commits the result). Pass `confirmInline: false` to opt out
/// (e.g. when the dialog body itself contains the warning).
class StealthDialogAction<T> {
  const StealthDialogAction({
    required this.label,
    required this.result,
    this.variant = StealthDialogActionVariant.secondary,
    this.confirmInline = true,
  });

  /// Convenience for the most common primary action.
  const StealthDialogAction.primary({
    required this.label,
    required this.result,
  })  : variant = StealthDialogActionVariant.primary,
        confirmInline = true;

  /// Convenience for a destructive action with the 2-tap gate.
  const StealthDialogAction.destructive({
    required this.label,
    required this.result,
    this.confirmInline = true,
  }) : variant = StealthDialogActionVariant.destructive;

  final String label;
  final T result;
  final StealthDialogActionVariant variant;
  final bool confirmInline;
}

/// Show a Stealth-branded dialog.
///
/// Replaces every bare `showDialog(builder: (_) => AlertDialog(...))`
/// in the app. Provides:
///
/// - Glass card body (`AppColors.backgroundSecondary` + glass border).
/// - Standardised `AppTypography.headline` title + body slot.
/// - Action row with `primary` / `secondary` / `destructive` variants.
/// - 2-tap "armed" gate for destructive actions.
/// - Optional `ScanlineOverlay` for `DialogImportance.high`.
///
/// Returns the `result` of the chosen action, or `null` if dismissed.
Future<T?> showStealthDialog<T>({
  required BuildContext context,
  required String title,
  Widget? body,
  List<StealthDialogAction<T>>? actions,
  bool barrierDismissible = true,
  DialogImportance importance = DialogImportance.normal,
}) {
  debugPrint('[ds:dialog] shown title=$title importance=$importance');
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _StealthDialog<T>(
      title: title,
      body: body,
      actions: actions ?? const [],
      importance: importance,
    ),
  );
}

class _StealthDialog<T> extends StatefulWidget {
  const _StealthDialog({
    required this.title,
    required this.body,
    required this.actions,
    required this.importance,
  });

  final String title;
  final Widget? body;
  final List<StealthDialogAction<T>> actions;
  final DialogImportance importance;

  @override
  State<_StealthDialog<T>> createState() => _StealthDialogState<T>();
}

class _StealthDialogState<T> extends State<_StealthDialog<T>> {
  /// Index of an action whose first tap has been observed but not
  /// yet confirmed (destructive 2-tap gate). `null` = nothing armed.
  int? _armedIndex;

  void _onActionTapped(int index) {
    final action = widget.actions[index];
    final needsConfirm =
        action.variant == StealthDialogActionVariant.destructive &&
            action.confirmInline;
    if (needsConfirm && _armedIndex != index) {
      debugPrint('[ds:dialog] destructive armed action=${action.label}');
      setState(() => _armedIndex = index);
      showStealthSnackBar(
        context,
        'Tap "${action.label}" again to confirm.',
        kind: SnackKind.warn,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    debugPrint('[ds:dialog] action=${action.label}');
    Navigator.of(context).pop(action.result);
  }

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: AppTypography.headline.copyWith(
              color: AppColors.textOnGlass,
            ),
          ),
          if (widget.body != null) ...[
            const SizedBox(height: AppSpacing.md),
            DefaultTextStyle.merge(
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              child: widget.body!,
            ),
          ],
          if (widget.actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < widget.actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  _ActionButton(
                    action: widget.actions[i],
                    armed: _armedIndex == i,
                    onTap: () => _onActionTapped(i),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (widget.importance == DialogImportance.high) {
      body = ScanlineOverlay(intensity: 1.0, child: body);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.glassMedium, width: 1),
          boxShadow: AppElevation.level3,
        ),
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.armed,
    required this.onTap,
  });

  final StealthDialogAction action;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    switch (action.variant) {
      case StealthDialogActionVariant.primary:
        return FilledButton(
          onPressed: onTap,
          child: Text(action.label),
        );
      case StealthDialogActionVariant.destructive:
        return FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: armed
                ? AppColors.statusDanger
                : AppColors.statusDanger.withValues(alpha: 0.85),
            foregroundColor: AppColors.textOnGlass,
          ),
          child: Text(armed ? 'Confirm: ${action.label}' : action.label),
        );
      case StealthDialogActionVariant.secondary:
        return TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textOnGlass,
          ),
          child: Text(action.label),
        );
    }
  }
}
