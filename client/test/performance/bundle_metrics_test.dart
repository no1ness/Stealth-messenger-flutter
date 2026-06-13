import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reports JS bundle / APK sizes. Skips when build artifacts are absent.
/// Designed for CI: run `flutter build web` or `flutter build apk` first.
void main() {
  test('web bundle size', () {
    final webFile = File('build/web/main.dart.js');
    if (!webFile.existsSync()) {
      print('--- Bundle Metrics (web): SKIPPED (build/web/ not found) ---');
      return;
    }
    final bytes = webFile.lengthSync();
    final kb = bytes / 1024;
    final mb = kb / 1024;
    print('--- Bundle Metrics (web) ---');
    print('main.dart.js: ${bytes} bytes (${kb.toStringAsFixed(1)} KB / '
        '${mb.toStringAsFixed(2)} MB)');
    expect(kb, lessThan(5000),
        reason: 'JS bundle should stay under 5 MB gzip-friendly');
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('apk bundle size', () {
    final apkDir = Directory('build/app/outputs/flutter-apk');
    if (!apkDir.existsSync()) {
      print('--- Bundle Metrics (APK): SKIPPED (build/app/ not found) ---');
      return;
    }
    final apks = apkDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.apk'))
        .toList();
    if (apks.isEmpty) {
      print('--- Bundle Metrics (APK): SKIPPED (no .apk files) ---');
      return;
    }
    for (final apk in apks) {
      final mb = apk.lengthSync() / (1024 * 1024);
      print('${apk.path}: ${mb.toStringAsFixed(1)} MB');
    }
  }, timeout: const Timeout(Duration(seconds: 10)));
}
