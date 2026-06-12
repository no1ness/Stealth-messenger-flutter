import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/liquid_theme.dart';
import 'package:stealth/ui/screens/startup_error_screen.dart';

/// Environment keys that can be overridden at build time via
/// `--dart-define=<key>=<value>`. Any non-empty value is pushed into
/// [dotenv.env] after the committed defaults load, so existing readers
/// (`dotenv.env[X]`) automatically pick up the override.
const List<String> _kDartDefineEnvKeys = <String>[
  'POCKETBASE_URL',
  'TURN_URL',
  'TURN_USERNAME',
  'TURN_PASSWORD',
  'TURNS_URL',
  'TURNS_USERNAME',
  'TURNS_PASSWORD',
];

void _applyDartDefineOverrides() {
  for (final key in _kDartDefineEnvKeys) {
    final fromDefine = _fromEnvironmentByKey(key);
    if (fromDefine.isNotEmpty) {
      dotenv.env[key] = fromDefine;
      Logger.info('[bootstrap] env key overridden via --dart-define',
          extras: {'key': key});
    }
  }
}

/// `String.fromEnvironment` only accepts compile-time constant names, so
/// the keys are spelled out explicitly here.
String _fromEnvironmentByKey(String key) {
  switch (key) {
    case 'POCKETBASE_URL':
      return const String.fromEnvironment('POCKETBASE_URL');
    case 'TURN_URL':
      return const String.fromEnvironment('TURN_URL');
    case 'TURN_USERNAME':
      return const String.fromEnvironment('TURN_USERNAME');
    case 'TURN_PASSWORD':
      return const String.fromEnvironment('TURN_PASSWORD');
    case 'TURNS_URL':
      return const String.fromEnvironment('TURNS_URL');
    case 'TURNS_USERNAME':
      return const String.fromEnvironment('TURNS_USERNAME');
    case 'TURNS_PASSWORD':
      return const String.fromEnvironment('TURNS_PASSWORD');
    default:
      return '';
  }
}

bool _isPlaceholderPocketbaseUrl(String url) {
  final lower = url.toLowerCase();
  return lower.endsWith('signal.example.com') ||
      lower.endsWith('signal.example.com/') ||
      lower.contains('change_me');
}

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
    final themeMode = _themeModeFromIndex(prefs.getInt('themeMode'));
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = themeMode;
    });
  }

  ThemeMode _themeModeFromIndex(int? index) {
    if (index == null || index < 0 || index >= ThemeMode.values.length) {
      return ThemeMode.system;
    }
    return ThemeMode.values[index];
  }

  Future<void> _initializeApp({bool afterReset = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _startupError = null;
      });
    }

    try {
      // Load committed defaults first. `.env.defaults` is bundled as an
      // asset (see pubspec.yaml) so this call always succeeds on a clean
      // clone and in CI. Real values come from `--dart-define` build
      // flags below or from local edits to `.env.defaults` — see the
      // file header for the override matrix.
      await dotenv.load(fileName: '.env.defaults');
      _applyDartDefineOverrides();

      final pocketbaseUrl = dotenv.env['POCKETBASE_URL']?.trim() ?? '';
      if (pocketbaseUrl.isEmpty || _isPlaceholderPocketbaseUrl(pocketbaseUrl)) {
        throw Exception(
          'POCKETBASE_URL is unset or pointing at the bundled placeholder '
          '"$pocketbaseUrl". Provide a real signaling endpoint via '
          '--dart-define=POCKETBASE_URL=https://signal.your.tld (recommended) '
          'or by editing client/.env.defaults locally. See '
          'docs/POCKETBASE_SETUP.md for the full deployment guide.',
        );
      }
      Logger.info('[bootstrap] PocketBase URL configured',
          extras: {'url': pocketbaseUrl});

      _appService = LocalAppService();
      await _checkRegistration();
    } catch (error) {
      // Corrupted secure storage (e.g. Android Keystore key rotated after a
      // reinstall with a different signing key) manifests as a BAD_DECRYPT
      // PlatformException. Recover once by wiping local credentials and any
      // persisted app session, then retrying the startup flow.
      if (!afterReset && _looksLikeCorruptSecureStorage(error)) {
        Logger.warn('[bootstrap] corrupted local storage detected, resetting',
            extras: {'error': error});
        await _resetLocalCredentials();
        await _initializeApp(afterReset: true);
        return;
      }

      Logger.error('[bootstrap] init failed', extras: {'error': error});
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
      Logger.warn('[bootstrap] StorageService.deleteAll failed during recovery',
          extras: {'error': error});
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
