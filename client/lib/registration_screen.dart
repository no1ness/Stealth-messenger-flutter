import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/supabase_service.dart';
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
  final SupabaseService _supabaseService = SupabaseService();

  Future<void> _register() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    setState(() {
      _isLoading = true;
    });
    try {
      await _supabaseService.registerUser(nickname);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainTabs()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: $e'),
          backgroundColor: AppColors.systemRed,
        ),
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
                    'Secure & Private Messaging',
                    style: AppTypography.subheadline.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl * 2),
                  GlassTextField(
                    controller: _nicknameController,
                    labelText: 'Choose a Nickname',
                    hintText: 'Enter your alias...',
                    prefixIcon: const Icon(Icons.person_outline, color: AppColors.systemBlue),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: !_isLoading && _nicknameController.text.trim().isNotEmpty ? _register : null,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('GET STARTED'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'No phone number. No email.\nYour privacy is our priority.',
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
    );
  }
}
