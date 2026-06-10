import 'package:flutter/material.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';

class UpdatePromptScreen extends StatelessWidget {
  const UpdatePromptScreen({
    super.key,
    required this.status,
    required this.onUpdateNow,
    required this.onSkip,
  });

  final AppUpdateStatus status;
  final Future<void> Function() onUpdateNow;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final manifest = status.manifest;
    final latest = manifest?.latestVersion.display ?? 'unknown';
    final current = status.currentVersion?.display ?? 'unknown';
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.system_update,
                    size: 56,
                    color: status.isMandatory
                        ? AppColors.systemOrange
                        : AppColors.systemBlue,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    status.isMandatory ? 'Update required' : 'Update available',
                    textAlign: TextAlign.center,
                    style: AppTypography.largeTitle,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Current: $current\nLatest: $latest',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (manifest != null && manifest.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Release notes', style: AppTypography.headline),
                    const SizedBox(height: AppSpacing.sm),
                    Text(manifest.releaseNotes, style: AppTypography.body),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: onUpdateNow,
                    icon: const Icon(Icons.download),
                    label: const Text('Update now'),
                  ),
                  if (!status.isMandatory) ...[
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: onSkip,
                      child: const Text('Not now'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
