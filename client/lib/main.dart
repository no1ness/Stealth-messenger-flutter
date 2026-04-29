import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/sync_service.dart';
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

  Future<void> _initializeSupabase({bool afterReset = false}) async {
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

      final prefs = await SharedPreferences.getInstance();
      final useSupabase = prefs.getBool('useSupabase') ?? true;
      final customUrl = prefs.getString('customSupabaseUrl');

      if (useSupabase) {
        await Supabase.initialize(
          url: (customUrl != null && customUrl.isNotEmpty) ? customUrl : supabaseUrl,
          anonKey: supabaseAnonKey,
        );
      }

      // Start background sync: pushes offline messages when connectivity returns.
      SyncService.instance.start();

      _supabaseService = SupabaseService();
      await _checkRegistration();
    } catch (error) {
      // Corrupted secure storage (e.g. Android Keystore key rotated after a
      // reinstall with a different signing key) manifests as a BAD_DECRYPT
      // PlatformException. Recover once by wiping local credentials and any
      // persisted Supabase session, then retrying the startup flow.
      if (!afterReset && _looksLikeCorruptSecureStorage(error)) {
        debugPrint(
          'Detected corrupted local storage during startup, resetting: $error',
        );
        await _resetLocalCredentials();
        await _initializeSupabase(afterReset: true);
        return;
      }

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

  /// Returns true for startup failures that look like unrecoverable cipher
  /// errors from `flutter_secure_storage` / Android Keystore.
  bool _looksLikeCorruptSecureStorage(Object error) {
    if (error is PlatformException) {
      final haystack = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (haystack.contains('bad_decrypt') ||
          haystack.contains('cipher') ||
          haystack.contains('aead')) {
        return true;
      }
    }
    return error.toString().toLowerCase().contains('bad_decrypt');
  }

  /// Clears every piece of local state that could keep a broken cipher around:
  /// our secure storage (identity keys, nickname, userId) and the Supabase
  /// session persisted in SharedPreferences. Swallows nested failures so that
  /// a partial wipe still lets the retry proceed on a cleaner slate.
  Future<void> _resetLocalCredentials() async {
    try {
      await StorageService().deleteAll();
    } catch (error) {
      debugPrint('StorageService.deleteAll failed during recovery: $error');
      for (final key in const [
        'userId',
        'nickname',
        'privateKey',
        'publicKey',
      ]) {
        try {
          await StorageService().delete(key);
        } catch (_) {
          // Best effort: ignore individual delete failures.
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final staleKeys = prefs
          .getKeys()
          .where((key) => key.startsWith('sb-') || key.contains('supabase'))
          .toList();
      for (final key in staleKeys) {
        await prefs.remove(key);
      }
    } catch (error) {
      debugPrint('Failed to purge Supabase prefs during recovery: $error');
    }
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
                  onWorkOffline: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('useSupabase', false);
                    _initializeSupabase();
                  },
                )
              : _isUserRegistered
                  ? const MainTabs()
                  : const RegistrationScreen(),
    );
  }
}
