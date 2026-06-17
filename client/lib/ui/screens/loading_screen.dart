import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_motion.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/motion/decrypt_text.dart';
import 'package:stealth/themes/apple_liquid/widgets/circuit_board_background.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';

/// App bootstrap screen.
///
/// Visually choreographed as a short "boot sequence" — the user lands
/// on a `CircuitBoardBackground` (system-coming-up flavour) and the
/// background crossfades to `StealthAnimatedBackground` (the app's
/// home surface) as the last step completes. Step labels render in a
/// glass card with a monospace step counter so the moment reads as
/// telemetry, not a marketing splash.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, this.initialChatId});

  final String? initialChatId;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  final List<String> _steps = const [
    'Инициализация защищенной сессии',
    'Загрузка чатов',
    'Подготовка адаптивного интерфейса',
  ];
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    for (var index = 0; index < _steps.length; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() => _currentStep = index);
    }

    if (!mounted) return;

    // Give the background crossfade a beat to land before the nav cut,
    // so the handoff feels like the system finishing booting rather
    // than a hard screen swap.
    await Future<void>.delayed(AppMotion.slow);
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            MainTabs(initialChatId: widget.initialChatId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastStep = _currentStep >= _steps.length - 1;
    final stepCounter =
        '${(_currentStep + 1).toString().padLeft(2, '0')} / '
        '${_steps.length.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Bottom layer: stealth animated background, always present.
          // Becomes visible as the circuit-board layer fades out.
          const StealthAnimatedBackground(child: SizedBox.expand()),
          // Top layer: circuit-board "boot sequence". Crossfades to
          // transparent as bootstrap reaches the last step — the
          // animated background underneath becomes the new canvas.
          AnimatedOpacity(
            duration: AppMotion.slow,
            curve: AppMotion.emphasized,
            opacity: isLastStep ? 0.0 : 1.0,
            child: CircuitBoardBackground(
              animated: true,
              child: const SizedBox.expand(),
            ),
          ),
          // Foreground: glass card with the boot-sequence telemetry.
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: GlassContainer(
                    intensity: GlassIntensity.light,
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          size: 64,
                          color: AppColors.systemBlue,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // Signature decryption-glitch reveal. The
                        // wordmark animates from random hex chars to
                        // STEALTH over `AppMotion.slow` — the first
                        // thing every user sees on cold launch.
                        DecryptText(
                          'STEALTH',
                          style: AppTypography.title1.copyWith(
                            fontFamily: AppTypography.fontFamilyMono,
                            fontFamilyFallback: AppFontStacks.monoFallbacks,
                            letterSpacing: 4,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          stepCounter,
                          style: AppTypography.captionMono.copyWith(
                            color: AppColors.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (_currentStep + 1) / _steps.length,
                            minHeight: 4,
                            backgroundColor:
                                AppColors.glassMedium.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.systemBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AnimatedSwitcher(
                          duration: AppMotion.normal,
                          child: Text(
                            _steps[_currentStep],
                            key: ValueKey<int>(_currentStep),
                            textAlign: TextAlign.center,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
