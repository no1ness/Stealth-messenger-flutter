import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/registration_screen.dart';
import 'liquid_theme.dart';
import 'screens/liquid_main_screen.dart';

/// Apple Liquid Glass UI Theme App Entry Point
/// 
/// This is an alternative app entry point using the Apple Liquid Glass theme.
/// To use this theme, update your main.dart to use AppleLiquidApp instead of MyApp.
class AppleLiquidApp extends StatefulWidget {
  const AppleLiquidApp({super.key});

  @override
  State<AppleLiquidApp> createState() => _AppleLiquidAppState();
}

class _AppleLiquidAppState extends State<AppleLiquidApp> {
  bool _isUserRegistered = false;
  bool _isLoading = true;
  final SupabaseService _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _checkUserRegistration();
  }

  Future<void> _checkUserRegistration() async {
    final String? userId = await _supabaseService.getUserId();
    setState(() {
      _isUserRegistered = userId != null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Turbo - Apple Liquid',
      debugShowCheckedModeBanner: false,
      theme: LiquidTheme.theme,
      home: _isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _isUserRegistered
              ? const LiquidMainScreen()
              : const RegistrationScreen(), // Use original registration for now
    );
  }
}
