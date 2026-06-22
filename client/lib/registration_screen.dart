import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

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
      TgHaptics.medium();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainTabs()),
      );
    } catch (e) {
      if (!mounted) return;
      TgSnackBar.show(
        context,
        'Ошибка регистрации: $e',
        isError: true,
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
    final c = TgThemeColors.of(context);

    final isWeb = kIsWeb;

    final content = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.security_rounded,
                  size: 80,
                  color: c.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'STEALTH',
                  style: TgTypography.largeTitle.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Безопасный и приватный мессенджер',
                  style: TgTypography.subheadline.copyWith(
                    color: c.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 64),
                TgTextField(
                  controller: _nicknameController,
                  labelText: 'Выберите никнейм',
                  hintText: 'Введите ваш алиас...',
                  prefixIcon: Icon(Icons.person_outline,
                      color: c.primary),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: !_isLoading &&
                            _nicknameController.text.trim().isNotEmpty
                        ? _register
                        : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: c.primary,
                        width: 1.5,
                      ),
                      foregroundColor: c.primary,
                      backgroundColor:
                          c.primary.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? TgLoading.spinner(
                            size: 20,
                          )
                        : const Text('НАЧАТЬ'),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Без номера телефона. Без email.\nВаша приватность — наш приоритет.',
                  style: TgTypography.caption1.copyWith(
                    color: c.textSecondary.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: c.background,
      body: content,
    );
  }
}
