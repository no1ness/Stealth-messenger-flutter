import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stealth/test_account_selection_screen.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/liquid_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'minimal_test_app.dart'; // Для тестирования

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Полная версия STEALTH с Supabase и всеми функциями
  runApp(const MyApp());

  // Для тестирования минимальной версии без Supabase:
  // runApp(const MinimalTestApp());
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

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initializeSupabase();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 2; // 2 = ThemeMode.system
    _themeMode = ThemeMode.values[themeIndex];
    if (mounted) setState(() {});
  }

  Future<void> _initializeSupabase() async {
    try {
      // Load environment variables (optional for web)
      try {
        await dotenv.load(fileName: ".env");
      } catch (e) {
        debugPrint('Warning: Could not load .env file: $e');
      }

      // Initialize Supabase with environment variables
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );

      // Теперь создаем SupabaseService после успешной инициализации
      _supabaseService = SupabaseService();
      await _autoLoginAsGeekom();
    } catch (e) {
      debugPrint('Error initializing Supabase: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _autoLoginAsGeekom() async {
    if (_supabaseService == null) return;

    setState(() => _isLoading = true);

    try {
      // Автоматический вход как GEEKOM
      await _supabaseService!.loginAsTestUser(
        userId: '22222222-2222-2222-2222-222222222222',
        nickname: 'GEEKOM'
      );


      setState(() {
        _isUserRegistered = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Auto-login failed: $e');
      setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stealth',
      themeMode: _themeMode,
      theme: LiquidTheme.theme, // Liquid Glass theme!
      darkTheme: LiquidTheme.darkTheme, // Темная версия темы
      home: _isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _isUserRegistered
              ? const MainTabs() // Сразу на главный экран
              : const TestAccountSelectionScreen(), // Экран выбора тестового аккаунта
    );
  }
}
