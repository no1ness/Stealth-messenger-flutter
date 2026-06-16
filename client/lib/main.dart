import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stealth/bootstrap_env.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/services/device/device_registry_service.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_loading_indicator.dart';
import 'package:stealth/themes/apple_liquid/liquid_theme.dart';
import 'package:stealth/themes/theme_controller.dart';
import 'package:stealth/ui/screens/startup_error_screen.dart';

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
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initializeApp();
  }

  Future<void> _loadTheme() async {
    // The controller writes ThemeController.mode itself; the
    // `ValueListenableBuilder` in `build()` picks the new value up.
    // No local setState needed.
    await ThemeController.loadInitial();
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
      applyDartDefineOverrides();

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
      await DeviceRegistryService.instance.init();
      await _appService?.startPBBasedWorkers();
      await _checkRegistration();
    } catch (error) {
      // Corrupted secure storage (e.g. Android Keystore key rotated after a
      // reinstall with a different signing key) manifests as a BAD_DECRYPT
      // PlatformException. Recover once by wiping local credentials and any
      // persisted app session, then retrying the startup flow.
      if (!afterReset && _looksLikeCorruptSecureStorage(error)) {
        Logger.warn(
            '[bootstrap] corrupted local storage detected, resetting',
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
    // Listen to the global theme controller so the Settings toggle
    // takes effect immediately, without restarting the app.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, controllerMode, _) {
        return MaterialApp(
          title: 'Stealth',
          debugShowCheckedModeBanner: false,
          themeMode: controllerMode,
          theme: LiquidTheme.theme,
          darkTheme: LiquidTheme.darkTheme,
          home: _isLoading
              ? const Scaffold(
                  body: Center(child: StealthLoadingIndicator()),
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
      },
    );
  }
}
