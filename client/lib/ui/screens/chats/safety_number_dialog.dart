import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stealth/di.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';

/// Dialog that renders the SHA-256 safety-number fingerprint of a
/// contact and lets the user record an out-of-band verification.
///
/// Returns `true` from [Navigator.pop] when the user confirms the
/// fingerprint matches (and [LocalAppService.verifyContact] has been
/// persisted), `false` on cancel, `null` if dismissed.
class SafetyNumberDialog extends ConsumerStatefulWidget {
  const SafetyNumberDialog({
    super.key,
    required this.contactUserId,
    required this.contactName,
  });

  final String contactUserId;
  final String contactName;

  /// Convenience wrapper around [showDialog].
  ///
  /// `await SafetyNumberDialog.show(context, userId, name)` returns the
  /// same tri-state value as `Navigator.pop` (true / false / null).
  static Future<bool?> show(
    BuildContext context, {
    required String contactUserId,
    required String contactName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => SafetyNumberDialog(
        contactUserId: contactUserId,
        contactName: contactName,
      ),
    );
  }

  @override
  ConsumerState<SafetyNumberDialog> createState() =>
      _SafetyNumberDialogState();
}

class _SafetyNumberDialogState extends ConsumerState<SafetyNumberDialog> {
  late Future<String?> _safetyNumberFuture;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _safetyNumberFuture =
        ref.read(localAppServiceProvider).getSafetyNumber(widget.contactUserId);
  }

  Future<void> _confirm(String safetyNumber) async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      await ref
          .read(localAppServiceProvider)
          .verifyContact(widget.contactUserId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _confirming = false;
        _error = 'Could not save verification: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Safety number — ${widget.contactName}'),
      content: FutureBuilder<String?>(
        future: _safetyNumberFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              width: 280,
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final safetyNumber = snapshot.data;
          if (safetyNumber == null || safetyNumber.isEmpty) {
            return SizedBox(
              width: 280,
              child: Text(
                'Safety number unavailable. Make sure the contact bundle '
                'includes a public key, then try again.',
                style: AppTypography.body.copyWith(
                  color: AppColors.systemOrange,
                ),
              ),
            );
          }

          return SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Compare these characters with the same screen on your '
                  "contact's device. If they match exactly your "
                  'end-to-end keys agree and no one has substituted them '
                  'on the wire.',
                  style: AppTypography.caption1
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                SelectableText(
                  safetyNumber,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    fontFamily: 'Courier',
                    color: AppColors.systemBlue,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Tap "Mark as verified" only after the two strings '
                  'match. The verification is stored locally and the '
                  'contacts list will show a check mark.',
                  style: AppTypography.caption2
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: AppTypography.body.copyWith(
                      color: AppColors.systemRed,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed:
              _confirming ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FutureBuilder<String?>(
          future: _safetyNumberFuture,
          builder: (context, snapshot) {
            final safetyNumber = snapshot.data;
            final canConfirm = !_confirming &&
                snapshot.connectionState == ConnectionState.done &&
                safetyNumber != null &&
                safetyNumber.isNotEmpty;
            return FilledButton(
              onPressed: canConfirm ? () => _confirm(safetyNumber) : null,
              child: _confirming
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Mark as verified'),
            );
          },
        ),
      ],
    );
  }
}
