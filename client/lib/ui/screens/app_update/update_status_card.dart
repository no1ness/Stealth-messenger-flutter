import 'package:flutter/material.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

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
    final c = TgThemeColors.of(context);
    final latest = status?.manifest?.latestVersion.display;
    final progress = installState?.progress;
    final canInstall = status?.isUpdateAvailable ?? false;
    return FlatContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Обновления', style: TgTypography.headline),
          const SizedBox(height: TgSpacing.md),
          Text('Stealth $appVersionLabel', style: TgTypography.title3),
          const SizedBox(height: TgSpacing.sm),
          Text(
            latest == null
                ? updateStatusLabel(status)
                : '${updateStatusLabel(status)}\nНовая: $latest',
            style: TgTypography.body.copyWith(color: c.textSecondary),
          ),
          if (isInstallingUpdate) ...[
            const SizedBox(height: TgSpacing.md),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: TgSpacing.sm),
            Text(
              installState?.phase.name ?? 'preparing',
              style: TgTypography.caption1.copyWith(
                color: c.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: TgSpacing.md),
          OutlinedButton.icon(
            onPressed: isCheckingUpdate ? null : onCheckForUpdates,
            icon: const Icon(Icons.refresh),
            label: Text(isCheckingUpdate ? 'Проверка...' : 'Проверить обновления'),
          ),
          if (canInstall) ...[
            const SizedBox(height: TgSpacing.sm),
            FilledButton.icon(
              onPressed: isInstallingUpdate ? null : onInstallUpdate,
              icon: const Icon(Icons.download),
              label: const Text('Обновить сейчас'),
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
      return 'У вас последняя версия';
    case AppUpdateStatusKind.optionalUpdateAvailable:
      return 'Доступно обновление';
    case AppUpdateStatusKind.mandatoryUpdateAvailable:
      return 'Требуется обновление';
    case AppUpdateStatusKind.unsupportedPlatform:
      return 'Обновление APK доступно только на Android';
    case AppUpdateStatusKind.notConfigured:
      return 'Проверка обновлений не настроена';
    case AppUpdateStatusKind.checkFailed:
      return 'Ошибка проверки обновлений';
    case null:
      return 'Статус обновления неизвестен';
  }
}
