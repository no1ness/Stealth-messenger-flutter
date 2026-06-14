import 'package:flutter/material.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';

class UpdateStatusCard extends StatelessWidget {
  const UpdateStatusCard({
    super.key,
    required this.appVersionLabel,
    required this.status,
    required this.installState,
    required this.isCheckingUpdate,
    required this.isInstallingUpdate,
    required this.onCheckForUpdates,
    required this.onInstallUpdate,
  });

  final String appVersionLabel;
  final AppUpdateStatus? status;
  final AppUpdateInstallState? installState;
  final bool isCheckingUpdate;
  final bool isInstallingUpdate;
  final VoidCallback onCheckForUpdates;
  final VoidCallback onInstallUpdate;

  @override
  Widget build(BuildContext context) {
    final latest = status?.manifest?.latestVersion.display;
    final progress = installState?.progress;
    final canInstall = status?.isUpdateAvailable ?? false;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Updates', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          Text('Stealth $appVersionLabel', style: AppTypography.title3),
          const SizedBox(height: AppSpacing.sm),
          Text(
            latest == null
                ? updateStatusLabel(status)
                : '${updateStatusLabel(status)}\nLatest: $latest',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          if (isInstallingUpdate) ...[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: AppSpacing.sm),
            Text(
              installState?.phase.name ?? 'preparing',
              style: AppTypography.caption1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: isCheckingUpdate ? null : onCheckForUpdates,
            icon: const Icon(Icons.refresh),
            label: Text(isCheckingUpdate ? 'Checking...' : 'Check for updates'),
          ),
          if (canInstall) ...[
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: isInstallingUpdate ? null : onInstallUpdate,
              icon: const Icon(Icons.download),
              label: const Text('Update now'),
            ),
          ],
        ],
      ),
    );
  }
}

String updateStatusLabel(AppUpdateStatus? status) {
  switch (status?.kind) {
    case AppUpdateStatusKind.upToDate:
      return 'You are up to date';
    case AppUpdateStatusKind.optionalUpdateAvailable:
      return 'Update available';
    case AppUpdateStatusKind.mandatoryUpdateAvailable:
      return 'Required update available';
    case AppUpdateStatusKind.unsupportedPlatform:
      return 'APK updates are supported only on Android';
    case AppUpdateStatusKind.notConfigured:
      return 'Update checks are not configured';
    case AppUpdateStatusKind.checkFailed:
      return 'Update check failed';
    case null:
      return 'Update status unknown';
  }
}
