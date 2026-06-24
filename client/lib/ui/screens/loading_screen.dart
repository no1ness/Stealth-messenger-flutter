import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

/// App bootstrap screen.
///
/// Visually choreographed as a short "boot sequence" — the user lands
/// on a ` SizedBox` (system-coming-up flavour) and the
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
  TgThemeColors get c => TgThemeColors.of(context);
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

    await Future<void>.delayed(const Duration(milliseconds: 300));
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
          const SizedBox.expand(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            opacity: isLastStep ? 0.0 : 1.0,
            child: const SizedBox.expand(),
          ),
          // Foreground: glass card with the boot-sequence telemetry.
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: EdgeInsets.all(TgSpacing.lg),
                  child: FlatContainer(
                    intensity: FlatIntensity.light,
                    padding: EdgeInsets.all(TgSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.security_rounded,
                          size: 64,
                          color: c.primary,
                        ),
                        SizedBox(height: TgSpacing.md),
                        // Signature decryption-glitch reveal. The
                        // wordmark animates from random hex chars to
                        // STEALTH over `` — the first
                        // thing every user sees on cold launch.
                        Text(
                          'STEALTH',
                          style: TgTypography.title1.copyWith(
                            fontFamily: TgTypography.fontFamilyMono,
                            fontFamilyFallback: ['monospace'],
                            letterSpacing: 4,
                            color: c.text,
                          ),
                        ),
                        SizedBox(height: TgSpacing.sm),
                        Text(
                          stepCounter,
                          style: TgTypography.captionMono.copyWith(
                            color: c.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: TgSpacing.md),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (_currentStep + 1) / _steps.length,
                            minHeight: 4,
                            backgroundColor:
                                c.surface.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              c.primary,
                            ),
                          ),
                        ),
                        SizedBox(height: TgSpacing.md),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _steps[_currentStep],
                            key: ValueKey<int>(_currentStep),
                            textAlign: TextAlign.center,
                            style: TgTypography.body.copyWith(
                              color: c.textSecondary,
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
