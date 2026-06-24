import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:js_interop';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stealth/bootstrap_env.dart';
import 'package:stealth/di.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/storage_service.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:flutter/foundation.dart';
import 'package:stealth/services/bypass/bypass_state_controller.dart';
import 'package:stealth/services/device/device_registry_service.dart';
import 'package:stealth/test_controller/test_controller.dart';
import 'package:stealth/test_controller/test_web_bridge.dart';
import 'package:stealth/themes/theme_controller.dart';
import 'package:stealth/ui/screens/startup_error_screen.dart';

bool _isPlaceholderPocketbaseUrl(String url) {
  final lower = url.toLowerCase();
  return lower.endsWith('signal.example.com') ||
      lower.endsWith('signal.example.com/') ||
      lower.contains('change_me');
}

@JS('window.localStorage.getItem')
external JSAny? _nativeGetItem(JSString key);

@JS('window.eval')
external JSAny? _nativeEval(JSString code);

String? _readLocalStorage(String key) {
  try {
    final result = _nativeGetItem(key.toJS);
    if (result == null) return null;
    if (result.isA<JSString>()) return (result as JSString).toDart;
    return result.toString();
  } catch (_) {
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
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
    _initializeApp();
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
          'Переменная POCKETBASE_URL не задана или указывает на заглушку '
          '"$pocketbaseUrl". Укажите реальный сигнальный эндпоинт через '
          '--dart-define=POCKETBASE_URL=https://signal.your.tld (рекомендуется) '
          'или отредактировав client/.env.defaults локально. См. '
          'docs/POCKETBASE_SETUP.md для полного руководства по развертыванию.',
        );
      }
      Logger.info('[bootstrap] PocketBase URL configured',
          extras: {'url': pocketbaseUrl});

      _appService = LocalAppService();
      _appService!.init();
      TestController.instance.attach();
      attachWebTestBridge(_appService!);
      await ThemeController.loadInitial();
      await _checkRegistration();
      await BypassStateController.init();
      Logger.info('[bootstrap] bypass state initialized');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        DeviceRegistryService.instance.init();
        _appService?.startPBBasedWorkers();
      });
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
    var userId = await _appService?.getUserId();

    // Fallback: if SharedPreferences/encryption can't resolve the userId,
    // check if the raw encrypted blob exists in localStorage.
    if (userId == null || userId.isEmpty) {
      userId = await _checkRegistrationFallback();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isUserRegistered = userId != null && userId.isNotEmpty;
      _isLoading = false;
      _startupError = null;
    });
  }

  /// Direct localStorage fallback for web builds where SharedPreferences
  /// may cache stale state after a page reload.
  Future<String?> _checkRegistrationFallback() async {
    if (!kIsWeb) return null;
    try {
      final raw = _readLocalStorage('flutter.userId');
      if (raw == null || raw.isEmpty) return null;
      // Check if stealthCrypto can decrypt it (means the key matches)
      final test = _nativeEval(
        '(function() { try { return typeof window.stealthCrypto !== "undefined" ? "ok" : "no-crypto"; } catch(e) { return "err"; } })()'.toJS,
      );
      final cryptoReady = test != null && test.toString() == 'ok';
      if (!cryptoReady) return null;
      // Return a non-null sentinel to indicate userId exists
      return 'registered';
    } catch (_) {
      return null;
    }
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
    return Consumer(
      builder: (context, ref, _) {
        final themeMode = ref.watch(themeModeProvider);
        return MaterialApp(
          title: 'Stealth',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: TgThemeData.light,
          darkTheme: TgThemeData.dark,
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
      },
    );
  }
}
