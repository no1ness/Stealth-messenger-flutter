import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/services/app_update/app_update_service.dart';

void main() {
  group('AppUpdateService', () {
    test('returns notConfigured when manifest URL is blank', () async {
      final service = AppUpdateService(
        manifestUrl: '',
        currentVersionProvider: () async => _version('0.1.0', 1),
        platformSupportedProvider: () => true,
      );

      final status = await service.checkForUpdate(source: 'test');

      expect(status.kind, AppUpdateStatusKind.notConfigured);
      expect(status.currentVersion?.display, '0.1.0+1');
    });

    test('returns unsupportedPlatform before manifest fetch', () async {
      var fetched = false;
      final service = AppUpdateService(
        manifestUrl: 'https://updates.example.com/manifest.json',
        currentVersionProvider: () async => _version('0.1.0', 1),
        platformSupportedProvider: () => false,
        manifestLoader: (_) async {
          fetched = true;
          return _manifestJson();
        },
      );

      final status = await service.checkForUpdate(source: 'test');

      expect(status.kind, AppUpdateStatusKind.unsupportedPlatform);
      expect(fetched, isFalse);
    });

    test('rejects non-HTTPS manifest URL safely', () async {
      final service = AppUpdateService(
        manifestUrl: 'http://updates.example.com/manifest.json',
        currentVersionProvider: () async => _version('0.1.0', 1),
        platformSupportedProvider: () => true,
      );

      final status = await service.checkForUpdate(source: 'test');

      expect(status.kind, AppUpdateStatusKind.checkFailed);
      expect(status.detail, contains('HTTPS'));
    });

    test('returns optional update for newer non-mandatory manifest', () async {
      final service = AppUpdateService(
        manifestUrl: 'https://updates.example.com/manifest.json',
        currentVersionProvider: () async => _version('0.1.0', 1),
        platformSupportedProvider: () => true,
        manifestLoader: (_) async => _manifestJson(),
      );

      final status = await service.checkForUpdate(source: 'test');

      expect(status.kind, AppUpdateStatusKind.optionalUpdateAvailable);
      expect(status.manifest?.latestVersion.display, '0.2.0+2');
    });

    test('returns mandatory update for mandatory manifest', () async {
      final service = AppUpdateService(
        manifestUrl: 'https://updates.example.com/manifest.json',
        currentVersionProvider: () async => _version('0.1.0', 1),
        platformSupportedProvider: () => true,
        manifestLoader: (_) async => _manifestJson(mandatory: true),
      );

      final status = await service.checkForUpdate(source: 'test');

      expect(status.kind, AppUpdateStatusKind.mandatoryUpdateAvailable);
      expect(status.isMandatory, isTrue);
    });

    test('manifest loader failure degrades to checkFailed', () async {
      final service = AppUpdateService(
        manifestUrl: 'https://updates.example.com/manifest.json',
        currentVersionProvider: () async => _version('0.1.0', 1),
        platformSupportedProvider: () => true,
        manifestLoader: (_) async => throw StateError('offline'),
      );

      final status = await service.checkForUpdate(source: 'test');

      expect(status.kind, AppUpdateStatusKind.checkFailed);
      expect(status.detail, contains('offline'));
    });
  });
}

AppUpdateVersion _version(String version, int buildNumber) {
  return AppUpdateVersion(version: version, buildNumber: buildNumber);
}

Map<String, Object?> _manifestJson({bool mandatory = false}) {
  return {
    'version': '0.2.0',
    'buildNumber': 2,
    'apkUrl': 'https://updates.example.com/stealth.apk',
    'sha256': 'c' * 64,
    'mandatory': mandatory,
    'releaseNotes': 'Release notes',
  };
}
