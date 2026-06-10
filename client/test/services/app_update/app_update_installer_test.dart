import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/app_update/app_update_installer_io.dart';
import 'package:stealth/services/app_update/app_update_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateInstaller', () {
    const channel = MethodChannel('stealth/app_update_test');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('verifies checksum and hands APK path to Android channel', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('stealth-update-test');
      final apk = File('${tempDir.path}/update.apk');
      await apk.writeAsString('apk-bytes');
      final manifest = _manifest(sha256: _sha256Hex('apk-bytes'));
      final states = <AppUpdateInstallPhase>[];
      String? receivedPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'installApk');
        receivedPath = (call.arguments as Map)['path'] as String;
        return null;
      });
      final installer = AppUpdateInstaller(
        channel: channel,
        apkDownloader: (_, onState) async => apk,
        platformSupportedProvider: () => true,
      );

      await installer.installUpdate(
        manifest,
        onState: (state) => states.add(state.phase),
      );

      expect(receivedPath, apk.path);
      expect(states, contains(AppUpdateInstallPhase.verifying));
      expect(states, contains(AppUpdateInstallPhase.readyToInstall));
      expect(states, contains(AppUpdateInstallPhase.completed));
      await tempDir.delete(recursive: true);
    });

    test('fails on checksum mismatch before channel handoff', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('stealth-update-test');
      final apk = File('${tempDir.path}/update.apk');
      await apk.writeAsString('wrong-bytes');
      var channelCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        channelCalled = true;
        return null;
      });
      final installer = AppUpdateInstaller(
        channel: channel,
        apkDownloader: (_, onState) async => apk,
        platformSupportedProvider: () => true,
      );

      await expectLater(
        installer.installUpdate(_manifest(sha256: 'd' * 64)),
        throwsA(isA<StateError>()),
      );
      expect(channelCalled, isFalse);
      await tempDir.delete(recursive: true);
    });
  });
}

AppUpdateManifest _manifest({required String sha256}) {
  return AppUpdateManifest(
    latestVersion: AppUpdateVersion(version: '0.2.0', buildNumber: 2),
    apkUrl: Uri.parse('https://updates.example.com/stealth.apk'),
    sha256: sha256,
    mandatory: false,
    releaseNotes: 'Release notes',
  );
}

String _sha256Hex(String text) {
  // SHA-256('apk-bytes') generated once to keep the test free of async crypto.
  if (text == 'apk-bytes') {
    return '1e10ba560383b17472b4cf72fef8f9e76c66815a3e6ae8c5a9b0c5e696b0bdf8';
  }
  throw ArgumentError.value(text, 'text', 'unexpected fixture');
}
