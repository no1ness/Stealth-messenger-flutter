// Runtime environment snapshot used by the diagnostics report header.
//
// Reads version metadata via `package_info_plus`, log level from
// `Logger.currentLevel`, and PocketBase host from `dotenv.env` directly
// to avoid triggering `PocketBaseClient.instance` (which throws on a
// missing URL).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../logging/logger.dart';

class AppEnvironmentInfo {
  const AppEnvironmentInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.locale,
    required this.logLevel,
    required this.pocketbaseHost,
  });

  final String appVersion;
  final String buildNumber;
  final String platform;
  final String locale;
  final String logLevel;
  final String? pocketbaseHost;

  static Future<AppEnvironmentInfo> collect() async {
    String version = 'unknown';
    String build = 'unknown';
    try {
      final pkg = await PackageInfo.fromPlatform();
      version = pkg.version;
      build = pkg.buildNumber;
    } catch (error) {
      // package_info_plus can throw on bare test environments — degrade
      // gracefully rather than failing the whole snapshot.
      Logger.warn('[diag.env] package info unavailable',
          extras: {'error': error});
    }

    final platform = kIsWeb ? 'web' : Platform.operatingSystem;

    String locale = 'unknown';
    try {
      locale =
          WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    } catch (_) {
      // No binding — treat as unknown.
    }

    final raw = dotenv.env['POCKETBASE_URL']?.trim();
    String? host;
    if (raw != null && raw.isNotEmpty) {
      final authority = Uri.tryParse(raw)?.authority;
      host = (authority != null && authority.isNotEmpty) ? authority : raw;
    }

    final info = AppEnvironmentInfo(
      appVersion: version,
      buildNumber: build,
      platform: platform,
      locale: locale,
      logLevel: Logger.currentLevel.name,
      pocketbaseHost: host,
    );
    Logger.info('[diag.env] collected', extras: {
      'platform': info.platform,
      'version': '${info.appVersion}+${info.buildNumber}',
      'pbHost': info.pocketbaseHost ?? 'unset',
    });
    return info;
  }
}
