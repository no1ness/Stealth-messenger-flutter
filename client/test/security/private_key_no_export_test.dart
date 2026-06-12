import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard: the project policy in `docs/SECURITY.md` and
/// `.ai-factory/rules/base.md` says the X25519 private identity key
/// must never leave the device. An older build leaked the key to
/// `<app docs>/stealth_private_key.txt`; that path is gone now and
/// this test makes sure it does not silently return.
///
/// The test scans every Dart source file under `client/lib/` and
/// fails if any line matches a pattern that would indicate the
/// private key is being written to disk, copied to the clipboard,
/// shared via the share sheet, or otherwise serialised.
void main() {
  test('client/lib never re-introduces private key export paths', () async {
    // Forbidden substring patterns. Each entry is a tuple of
    // (humanReadableLabel, RegExp). The regex is case-insensitive so
    // accidental variants like `StealthPrivateKey` also trip it.
    final forbiddenPatterns = <(String, RegExp)>[
      (
        'literal file name "stealth_private_key.txt"',
        RegExp(r'stealth_private_key', caseSensitive: false),
      ),
      (
        'writeAsString call referencing privateKey',
        RegExp(r'writeAsString.*privateKey', caseSensitive: false),
      ),
      (
        'writeAsBytes call referencing privateKey',
        RegExp(r'writeAsBytes.*privateKey', caseSensitive: false),
      ),
      (
        'Clipboard.setData carrying privateKey',
        RegExp(r'Clipboard\.setData[^;]*privateKey', caseSensitive: false),
      ),
      (
        'Share / Share.shareFiles call carrying privateKey',
        RegExp(r'Share[A-Za-z]*\.[A-Za-z]+\s*\([^;]*privateKey',
            caseSensitive: false),
      ),
    ];

    final libDir = Directory('lib');
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'client/lib must exist (run flutter test from client/)',
    );

    final dartFiles = libDir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(dartFiles, isNotEmpty,
        reason: 'no .dart sources found under client/lib');

    final violations = <String>[];
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        // Skip comments so legitimate references in docstrings ("the
        // legacy export at stealth_private_key.txt is forbidden")
        // do not trip the guard.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') ||
            trimmed.startsWith('///') ||
            trimmed.startsWith('*')) {
          continue;
        }
        for (final (label, pattern) in forbiddenPatterns) {
          if (pattern.hasMatch(line)) {
            violations.add('${file.path}:${index + 1}: $label\n  $line');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Private key export pattern reappeared in client/lib. Policy: the '
          'X25519 private identity key MUST stay on device (see '
          'docs/SECURITY.md). If you need to add an encrypted backup flow, '
          'design it explicitly and update this guard.\n\nViolations:\n'
          '${violations.join('\n')}',
    );
  });
}
