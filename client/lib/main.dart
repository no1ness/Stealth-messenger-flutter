import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/liquid_theme.dart';
import 'package:stealth/ui/screens/startup_error_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isUserRegistered = false;
  bool _isLoading = true;
  SupabaseService? _supabaseService;
  ThemeMode _themeMode = ThemeMode.system;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initializeSupabase();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = ThemeMode.values[themeIndex];
    });
  }

  Future<void> _initializeSupabase() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _startupError = null;
      });
    }

    try {
      // Env loading stays explicit so `flutter run` behaves the same on every target.
      await dotenv.load(fileName: '.env');
      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
      if (supabaseUrl == null ||
          supabaseUrl.isEmpty ||
          supabaseAnonKey == null ||
          supabaseAnonKey.isEmpty) {
        throw Exception(
          'Missing SUPABASE_URL or SUPABASE_ANON_KEY in client/.env.',
        );
      }

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );

      _supabaseService = SupabaseService();
      await _checkRegistration();
    } catch (error) {
      debugPrint('Error initializing Supabase: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _startupError = '$error';
      });
    }
  }

  Future<void> _checkRegistration() async {
    final userId = await _supabaseService?.getUserId();
    if (!mounted) {
      return;
    }

    setState(() {
      _isUserRegistered = userId != null && userId.isNotEmpty;
      _isLoading = false;
      _startupError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stealth',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: LiquidTheme.theme,
      darkTheme: LiquidTheme.darkTheme,
      home: _isLoading
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _startupError != null
              ? StartupErrorScreen(
                  message: _startupError!,
                  onRetry: _initializeSupabase,
                )
          : _isUserRegistered
              ? const MainTabs()
              : const RegistrationScreen(),
    );
  }
}
