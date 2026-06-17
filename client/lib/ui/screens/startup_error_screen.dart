import 'package:flutter/material.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StealthAnimatedBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.settings_ethernet,
                          size: 72,
                          color: AppColors.systemOrange,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Требуется настройка окружения',
                          textAlign: TextAlign.center,
                          style: AppTypography.title1.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Укажите настоящий POCKETBASE_URL одним из способов:',
                                textAlign: TextAlign.center,
                                style: AppTypography.caption1.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                '• flutter run --dart-define=POCKETBASE_URL=…\n'
                                '• отредактируйте client/.env.defaults\n'
                                '• см. docs/POCKETBASE_SETUP.md',
                                textAlign: TextAlign.left,
                                style: AppTypography.caption1.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton.icon(
                          onPressed: () => onRetry(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить запуск'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
