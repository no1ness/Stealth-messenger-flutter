import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/effects/grain_overlay.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_haptics.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_loading_indicator.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_snack_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  bool _isLoading = false;
  final LocalAppService _appService = LocalAppService();

  Future<void> _register() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    setState(() {
      _isLoading = true;
    });
    try {
      await _appService.registerUser(nickname);
      if (!mounted) return;
      StealthHaptics.success(context);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainTabs()),
      );
    } catch (e) {
      if (!mounted) return;
      showStealthSnackBar(
        context,
        'Ошибка регистрации: $e',
        kind: SnackKind.danger,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: StealthAnimatedBackground(
        child: GrainOverlay(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.security_rounded,
                      size: 80,
                      color: AppColors.systemBlue,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'STEALTH',
                      style: AppTypography.largeTitle.copyWith(
                        letterSpacing: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Безопасный и приватный мессенджер',
                      style: AppTypography.subheadline.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xxl * 2),
                    GlassTextField(
                      controller: _nicknameController,
                      labelText: 'Выберите никнейм',
                      hintText: 'Введите ваш алиас...',
                      prefixIcon: const Icon(Icons.person_outline,
                          color: AppColors.systemBlue),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    OutlinedButton(
                      onPressed: !_isLoading &&
                              _nicknameController.text.trim().isNotEmpty
                          ? _register
                          : null,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AppColors.systemBlue,
                          width: 1.5,
                        ),
                        foregroundColor: AppColors.systemBlue,
                        backgroundColor:
                            AppColors.systemBlue.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl,
                          vertical: AppSpacing.sm,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg),
                        ),
                      ),
                      child: _isLoading
                          ? const StealthLoadingIndicator(
                              size: 20,
                              strokeWidth: 2,
                            )
                          : const Text('НАЧАТЬ'),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Без номера телефона. Без email.\nВаша приватность — наш приоритет.',
                      style: AppTypography.caption1.copyWith(
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
