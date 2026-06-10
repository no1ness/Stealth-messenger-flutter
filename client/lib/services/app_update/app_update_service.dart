import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stealth/logging/logger.dart';

import 'app_update_manifest_loader.dart' as manifest_loader;
import 'app_update_models.dart';
import 'app_update_platform.dart' as app_update_platform;

typedef CurrentVersionProvider = Future<AppUpdateVersion> Function();
typedef UpdateManifestLoader = Future<Map<String, Object?>> Function(Uri uri);
typedef PlatformSupportedProvider = bool Function();

const String appUpdateManifestUrlKey = 'APP_UPDATE_MANIFEST_URL';

class AppUpdateService {
  AppUpdateService({
    String? manifestUrl,
    CurrentVersionProvider? currentVersionProvider,
    UpdateManifestLoader? manifestLoader,
    PlatformSupportedProvider? platformSupportedProvider,
  })  : _manifestUrl = manifestUrl,
        _currentVersionProvider =
            currentVersionProvider ?? _packageInfoVersionProvider,
        _manifestLoader = manifestLoader ?? manifest_loader.loadUpdateManifest,
        _platformSupportedProvider = platformSupportedProvider ??
            (() => app_update_platform.isAndroidInstallerSupported);

  factory AppUpdateService.fromEnv({
    CurrentVersionProvider? currentVersionProvider,
    UpdateManifestLoader? manifestLoader,
    PlatformSupportedProvider? platformSupportedProvider,
  }) {
    return AppUpdateService(
      manifestUrl: dotenv.env[appUpdateManifestUrlKey]?.trim(),
      currentVersionProvider: currentVersionProvider,
      manifestLoader: manifestLoader,
      platformSupportedProvider: platformSupportedProvider,
    );
  }

  final String? _manifestUrl;
  final CurrentVersionProvider _currentVersionProvider;
  final UpdateManifestLoader _manifestLoader;
  final PlatformSupportedProvider _platformSupportedProvider;

  Future<AppUpdateStatus> checkForUpdate({String source = 'manual'}) async {
    Logger.debug('[app-update] check started', extras: {'source': source});
    AppUpdateVersion? currentVersion;
    try {
      currentVersion = await _currentVersionProvider();
      Logger.debug('[app-update] current version resolved', extras: {
        'currentVersion': currentVersion.display,
        'source': source,
      });
    } catch (error) {
      Logger.warn('[app-update] current version unavailable', extras: {
        'error': error,
        'source': source,
      });
    }

    final rawManifestUrl = _manifestUrl?.trim() ?? '';
    if (rawManifestUrl.isEmpty) {
      final status =
          AppUpdateStatus.notConfigured(currentVersion: currentVersion);
      _logResolvedStatus(status, source: source);
      return status;
    }

    if (!_platformSupportedProvider()) {
      final status =
          AppUpdateStatus.unsupportedPlatform(currentVersion: currentVersion);
      _logResolvedStatus(status, source: source);
      return status;
    }

    final uri = Uri.tryParse(rawManifestUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      Logger.warn('[app-update] manifest URL invalid', extras: {
        'source': source,
        'manifestUrl': _safeUriLabel(uri),
      });
      final status = AppUpdateStatus.checkFailed(
        currentVersion: currentVersion,
        detail: '$appUpdateManifestUrlKey must be an absolute HTTPS URL.',
      );
      _logResolvedStatus(status, source: source);
      return status;
    }

    if (currentVersion == null) {
      final status = AppUpdateStatus.checkFailed(
          detail: 'Current app version is unavailable.');
      _logResolvedStatus(status, source: source);
      return status;
    }

    try {
      Logger.debug('[app-update] manifest fetch started', extras: {
        'source': source,
        'manifestUrl': _safeUriLabel(uri),
      });
      final json = await _manifestLoader(uri);
      final manifest = AppUpdateManifest.fromJson(json);
      final status = AppUpdateStatus.resolve(
        currentVersion: currentVersion,
        manifest: manifest,
        platformSupported: true,
      );
      _logResolvedStatus(status, source: source);
      return status;
    } catch (error) {
      Logger.warn('[app-update] manifest unavailable', extras: {
        'error': error,
        'source': source,
        'manifestUrl': _safeUriLabel(uri),
      });
      final status = AppUpdateStatus.checkFailed(
        currentVersion: currentVersion,
        detail: '$error',
      );
      _logResolvedStatus(status, source: source);
      return status;
    }
  }

  static Future<AppUpdateVersion> _packageInfoVersionProvider() async {
    final pkg = await PackageInfo.fromPlatform();
    return AppUpdateVersion.fromValues(
      version: pkg.version,
      buildNumber: pkg.buildNumber,
      fieldPrefix: 'packageInfo',
    );
  }

  void _logResolvedStatus(AppUpdateStatus status, {required String source}) {
    Logger.info('[app-update] update status resolved', extras: {
      'source': source,
      'status': status.kind.name,
      'currentVersion': status.currentVersion?.display ?? 'unknown',
      'latestVersion': status.manifest?.latestVersion.display,
    });
  }
}

String _safeUriLabel(Uri? uri) {
  if (uri == null) return 'invalid';
  final path = uri.path.isEmpty ? '/' : uri.path;
  return '${uri.scheme}://${uri.host}$path';
}
