import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the sensitive-key policy documented at the top
/// of `client/lib/storage_service.dart`.
///
/// The project keeps two storage paths:
///
/// 1. [StorageService] — encrypted (Keychain / EncryptedSharedPreferences
///    on mobile, Web Crypto AES-256-GCM with a non-extractable key on
///    web). Anything sensitive (private keys, auth tokens, group
///    secrets) **must** go through this layer.
/// 2. `SharedPreferences` — plain key/value store. Suitable only for
///    low-sensitivity UI state (`themeMode`, `useP2P`).
///
/// This test scans `lib/` for direct `SharedPreferences` access
/// (`setString`, `getString`, `remove`, …) keyed by any of the
/// sensitive names. If a future contributor accidentally writes a
/// private key, PB token, etc. to `SharedPreferences` the test fails
/// loudly with the offending file:line so the policy is impossible to
/// drift past silently.
///
/// `storage_service_*.dart` themselves are excluded because they are
/// the secure-storage abstraction and legitimately call
/// `SharedPreferences` under the hood — for web they store *encrypted
/// ciphertext* under those keys, not plaintext.
void main() {
  test('client/lib never writes sensitive keys to SharedPreferences directly',
      () async {
    // Names that may NEVER appear as a SharedPreferences key in `lib/`
    // (outside the `storage_service_*` backend files).
    const forbiddenKeys = <String>[
      'privateKey',
      'publicKey',
      'pb_token',
      'pb_password',
      'pb_user_id',
      'local_db_key',
      'userId',
      'nickname',
      'registeredAt',
      // `privateKey_prev` / `publicKey_prev` are reserved for Phase 5
      // (identity key rotation); banning them now prevents accidental
      // SharedPreferences leakage when that work lands.
      'privateKey_prev',
      'publicKey_prev',
      'prev_rotated_at',
    ];

    // Group keys are dynamic (`group_key_<chatId>`). Detect the prefix
    // by matching the literal `'group_key_` opener inside any
    // SharedPreferences call.
    const groupKeyPrefix = "'group_key_";

    final libDir = Directory('lib');
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'client/lib must exist (run flutter test from client/)',
    );

    // Storage backend files legitimately call SharedPreferences with
    // these keys to persist the *encrypted* payload — skip them.
    bool isStorageBackendFile(File file) {
      final name = file.uri.pathSegments.last;
      return name == 'storage_service_io.dart' ||
          name == 'storage_service_stub.dart' ||
          name == 'storage_service_web.dart';
    }

    final dartFiles = libDir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !isStorageBackendFile(file))
        .toList();
    expect(dartFiles, isNotEmpty,
        reason: 'no .dart sources found under client/lib');

    // For every forbidden key, build a regex that fires only when the
    // key sits inside a SharedPreferences accessor call. We accept
    // both `prefs.setString('privateKey', …)` and the rarer
    // `SharedPreferences().getString('privateKey')`.
    String escape(String s) =>
        s.replaceAllMapped(RegExp(r'[.\\+*?\[\]\(\)\{\}\|\$\^]'),
            (m) => '\\${m.group(0)}');
    final accessorOpener = RegExp(
      // Anchors on `SharedPreferences` directly, or on the conventional
      // `prefs` / `preferences` receivers, then a get*/set*/remove*/
      // contains*/reload accessor and the literal key string.
      r"(SharedPreferences\b[^;]*\.|\b(prefs|preferences|sp|sharedPrefs)\b\s*\.)\s*(get|set|remove|contains|reload)\w*\s*\(\s*",
    );

    final violations = <String>[];
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        final trimmed = line.trimLeft();
        // Skip comments so this very file's own examples don't trip the
        // guard.
        if (trimmed.startsWith('//') ||
            trimmed.startsWith('///') ||
            trimmed.startsWith('*')) {
          continue;
        }

        // Cheap rejection: only continue if the line looks like a
        // SharedPreferences accessor call.
        final accessorMatch = accessorOpener.firstMatch(line);
        if (accessorMatch == null) {
          continue;
        }

        final suffix = line.substring(accessorMatch.end);

        // Exact-name check.
        for (final key in forbiddenKeys) {
          final keyPattern =
              RegExp("['\"]${escape(key)}['\"]\\s*[,)]");
          if (keyPattern.hasMatch(suffix)) {
            violations
                .add('${file.path}:${index + 1}: SharedPreferences carrying '
                    'sensitive key "$key"\n  $line');
          }
        }

        // group_key_<…> prefix check.
        if (suffix.contains(groupKeyPrefix)) {
          violations.add(
              '${file.path}:${index + 1}: SharedPreferences carrying '
              'sensitive group key prefix "group_key_…"\n  $line');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Sensitive key written to SharedPreferences directly. Policy: '
          'private keys, auth tokens, DB / group secrets and identity '
          'fields MUST go through StorageService (see the doc comment at '
          'the top of client/lib/storage_service.dart). If a new low-'
          'sensitivity UI pref needs SharedPreferences, add the allowed '
          'name to the policy + this test.\n\nViolations:\n'
          '${violations.join('\n')}',
    );
  });
}
