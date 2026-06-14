import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/app_update/app_update_models.dart';

void main() {
  group('AppUpdateVersion', () {
    test('compares semver-like versions before build numbers', () {
      final current = AppUpdateVersion(version: '1.2.9', buildNumber: 50);
      final newer = AppUpdateVersion(version: '1.3.0', buildNumber: 1);

      expect(newer > current, isTrue);
      expect(current < newer, isTrue);
    });

    test('uses build number when version segments are equal', () {
      final current = AppUpdateVersion(version: '1.2.0', buildNumber: 10);
      final newer = AppUpdateVersion(version: '1.2', buildNumber: 11);

      expect(newer > current, isTrue);
      expect(newer.display, '1.2+11');
    });

    test('accepts prerelease or build metadata suffixes for comparison', () {
      final left = AppUpdateVersion(version: '1.2.3-beta.1', buildNumber: 1);
      final right = AppUpdateVersion(version: '1.2.3+release', buildNumber: 2);

      expect(right > left, isTrue);
    });

    test('rejects invalid version values with context', () {
      expect(
        () => AppUpdateVersion.fromValues(
          version: '1.two.0',
          buildNumber: 1,
          fieldPrefix: 'manifest',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AppUpdateManifest', () {
    test('parses required manifest fields', () {
      final manifest = AppUpdateManifest.fromJson({
        'version': '0.2.0',
        'buildNumber': '7',
        'apkUrl': 'https://updates.example.com/stealth.apk',
        'sha256': 'a' * 64,
        'mandatory': false,
        'releaseNotes': 'Bug fixes',
      });

      expect(manifest.latestVersion.display, '0.2.0+7');
      expect(manifest.apkUrl.host, 'updates.example.com');
      expect(manifest.sha256, 'a' * 64);
      expect(manifest.mandatory, isFalse);
    });

    test('rejects non-HTTPS APK URL', () {
      expect(
        () => AppUpdateManifest.fromJson({
          'version': '0.2.0',
          'buildNumber': 7,
          'apkUrl': 'http://updates.example.com/stealth.apk',
          'sha256': 'a' * 64,
          'mandatory': false,
          'releaseNotes': 'Bug fixes',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AppUpdateStatus', () {
    test('resolves up-to-date when manifest is not newer', () {
      final status = AppUpdateStatus.resolve(
        currentVersion: AppUpdateVersion(version: '0.2.0', buildNumber: 7),
        manifest: _manifest(version: '0.2.0', buildNumber: 7),
        platformSupported: true,
      );

      expect(status.kind, AppUpdateStatusKind.upToDate);
      expect(status.isUpdateAvailable, isFalse);
    });

    test('resolves optional and mandatory update availability', () {
      final optional = AppUpdateStatus.resolve(
        currentVersion: AppUpdateVersion(version: '0.1.0', buildNumber: 1),
        manifest: _manifest(version: '0.2.0', buildNumber: 2),
        platformSupported: true,
      );
      final mandatory = AppUpdateStatus.resolve(
        currentVersion: AppUpdateVersion(version: '0.1.0', buildNumber: 1),
        manifest: _manifest(
          version: '0.2.0',
          buildNumber: 2,
          mandatory: true,
        ),
        platformSupported: true,
      );

      expect(optional.kind, AppUpdateStatusKind.optionalUpdateAvailable);
      expect(optional.isMandatory, isFalse);
      expect(mandatory.kind, AppUpdateStatusKind.mandatoryUpdateAvailable);
      expect(mandatory.isMandatory, isTrue);
    });

    test('represents unsupported, not-configured and failed states', () {
      final current = AppUpdateVersion(version: '0.1.0', buildNumber: 1);

      expect(
        AppUpdateStatus.unsupportedPlatform(currentVersion: current).kind,
        AppUpdateStatusKind.unsupportedPlatform,
      );
      expect(
        AppUpdateStatus.notConfigured(currentVersion: current).kind,
        AppUpdateStatusKind.notConfigured,
      );
      expect(
        AppUpdateStatus.checkFailed(currentVersion: current, detail: 'failed')
            .kind,
        AppUpdateStatusKind.checkFailed,
      );
    });
  });

  group('AppUpdateInstallState', () {
    test('computes bounded download progress', () {
      final half = const AppUpdateInstallState(
        phase: AppUpdateInstallPhase.downloading,
        receivedBytes: 50,
        totalBytes: 100,
      );
      final overflow = const AppUpdateInstallState(
        phase: AppUpdateInstallPhase.downloading,
        receivedBytes: 150,
        totalBytes: 100,
      );

      expect(half.progress, 0.5);
      expect(overflow.progress, 1);
    });
  });
}

AppUpdateManifest _manifest({
  required String version,
  required int buildNumber,
  bool mandatory = false,
}) {
  return AppUpdateManifest(
    latestVersion: AppUpdateVersion(
      version: version,
      buildNumber: buildNumber,
    ),
    apkUrl: Uri.parse('https://updates.example.com/stealth.apk'),
    sha256: 'b' * 64,
    mandatory: mandatory,
    releaseNotes: 'Release notes',
  );
}
