import 'package:flutter/material.dart';

import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/effects/grain_overlay.dart';

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
        title = 'No conversations yet.',
        message =
            'Send a contact bundle to start a thread. Stealth is silent until you reach out.';

  /// Contacts list when the user has no contacts.
  const StealthEmptyState.contacts({super.key, this.action})
      : icon = Icons.person_add_alt_1_outlined,
        title = 'Your address book is private.',
        message =
            'Scan a contact bundle or paste an invite. Nothing leaves the device until you do.';

  /// Calls list when there is no recent call activity.
  const StealthEmptyState.calls({super.key, this.action})
      : icon = Icons.call_outlined,
        title = 'No calls. Stay silent.',
        message =
            'Outgoing or incoming — your history starts the first time you dial.';

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    debugPrint('[ds:empty-state] title=$title');
    return GrainOverlay(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 64,
                color: AppColors.textSecondary,
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
          title: 'Nothing to see here',
        );
    }
  }
}
