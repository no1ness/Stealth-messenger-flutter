import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

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
    final c = TgThemeColors.of(context);
    return Scaffold(
      body: Container(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(TgSpacing.xl),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(TgSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.settings_ethernet,
                          size: 72,
                          color: c.warning,
                        ),
                        const SizedBox(height: TgSpacing.lg),
                        Text(
                          'Требуется настройка окружения',
                          textAlign: TextAlign.center,
                          style: TgTypography.title1.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: TgSpacing.md),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TgTypography.body.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: TgSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(TgSpacing.md),
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
                                style: TgTypography.caption1.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: TgSpacing.sm),
                              Text(
                                '• flutter run --dart-define=POCKETBASE_URL=…\n'
                                '• отредактируйте client/.env.defaults\n'
                                '• см. docs/POCKETBASE_SETUP.md',
                                textAlign: TextAlign.left,
                                style: TgTypography.caption1.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: TgSpacing.lg),
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
