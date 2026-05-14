import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/local_app_service.dart';
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
  LocalAppService? _appService;
  ThemeMode _themeMode = ThemeMode.system;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initializeApp();
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

  Future<void> _initializeApp({bool afterReset = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _startupError = null;
      });
    }

    try {
      // Env loading stays explicit so `flutter run` behaves the same on every target.
      await dotenv.load(fileName: '.env');
      final pocketbaseUrl = dotenv.env['POCKETBASE_URL'];
      if (pocketbaseUrl == null || pocketbaseUrl.isEmpty) {
        throw Exception(
          'Missing POCKETBASE_URL in client/.env. WebRTC call signaling '
          'requires a PocketBase server - see docs/POCKETBASE_SETUP.md '
          'for setup instructions.',
        );
      }
      debugPrint('[stealth-call] PocketBase URL: $pocketbaseUrl');

      _appService = LocalAppService();
      await _checkRegistration();
    } catch (error) {
      // Corrupted secure storage (e.g. Android Keystore key rotated after a
      // reinstall with a different signing key) manifests as a BAD_DECRYPT
      // PlatformException. Recover once by wiping local credentials and any
      // persisted app session, then retrying the startup flow.
      if (!afterReset && _looksLikeCorruptSecureStorage(error)) {
        debugPrint(
          'Detected corrupted local storage during startup, resetting: $error',
        );
        await _resetLocalCredentials();
        await _initializeApp(afterReset: true);
        return;
      }

      debugPrint('Error initializing app: $error');
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
    final userId = await _appService?.getUserId();
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

  /// Clears every piece of local state that could keep a broken cipher around.
  /// Swallows nested failures so that a partial wipe still lets the retry
  /// proceed on a cleaner slate.
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
                  onRetry: _initializeApp,
                )
              : _isUserRegistered
                  ? const MainTabs()
                  : const RegistrationScreen(),
    );
  }
}
