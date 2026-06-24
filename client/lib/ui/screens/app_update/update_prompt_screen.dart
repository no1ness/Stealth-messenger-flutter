import 'package:flutter/material.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

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
    final c = TgThemeColors.of(context);

    final manifest = status.manifest;
    final latest = manifest?.latestVersion.display ?? 'unknown';
    final current = status.currentVersion?.display ?? 'unknown';
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TgSpacing.lg),
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
                        ? c.warning
                        : c.primary,
                  ),
                  const SizedBox(height: TgSpacing.md),
                  Text(
                    status.isMandatory ? 'Требуется обновление' : 'Доступно обновление',
                    textAlign: TextAlign.center,
                    style: TgTypography.largeTitle,
                  ),
                  const SizedBox(height: TgSpacing.md),
                  Text(
                    'Текущая: $current\nНовая: $latest',
                    textAlign: TextAlign.center,
                    style: TgTypography.body.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  if (manifest != null && manifest.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: TgSpacing.lg),
                    Text('Что нового', style: TgTypography.headline),
                    const SizedBox(height: TgSpacing.sm),
                    Text(manifest.releaseNotes, style: TgTypography.body),
                  ],
                  const SizedBox(height: TgSpacing.xl),
                  FilledButton.icon(
                    onPressed: onUpdateNow,
                    icon: const Icon(Icons.download),
                    label: const Text('Обновить сейчас'),
                  ),
                  if (!status.isMandatory) ...[
                    const SizedBox(height: TgSpacing.sm),
                    OutlinedButton(
                      onPressed: onSkip,
                      child: const Text('Не сейчас'),
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
