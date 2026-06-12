import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard: project rule `.ai-factory/rules/base.md` requires all
/// logging in `client/lib` to go through `Logger.*` from
/// `lib/logging/logger.dart`. Bare `debugPrint(` and `print(` calls are
/// forbidden outside of an explicit, shrinking allow-list.
///
/// The allow-list is intentionally hand-maintained — as files migrate
/// off `debugPrint`, REMOVE them from the set. The set must only ever
/// shrink. Task #4 of the hardening-followup plan lifts it to empty.
void main() {
  test('client/lib has no bare debugPrint/print outside allow-list', () async {
    // Paths relative to `client/`. These files are tolerated until
    // their migration tasks land. Never grow this set without a
    // corresponding entry in the active plan to migrate the file off.
    const allowList = <String>{
      // Logger's own sink — debugPrint is the actual output channel.
      // Everything else MUST go through Logger.{debug,info,warn,error}.
      'lib/logging/logger.dart',
    };

    // `debugPrint(` matches the literal call. `(?<![\w.])print\(` rejects
    // bare top-level `print(` while NOT matching `debugPrint(` (lookbehind
    // fails because the char before `print` is `g`, a word char).
    final forbiddenPatterns = <(String, RegExp)>[
      ('debugPrint(', RegExp(r'\bdebugPrint\(')),
      ('print(', RegExp(r'(?<![\w.])print\(')),
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
      // Normalise to forward slashes so the allow-list (authored with
      // POSIX separators) compares the same on Windows hosts.
      final relativePath = file.path.replaceAll(r'\', '/');
      if (allowList.contains(relativePath)) {
        continue;
      }

      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
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
      reason: 'Bare debugPrint/print appeared in client/lib outside the '
          'allow-list. Policy: route all logging through `Logger.*` '
          '(see `lib/logging/logger.dart`). If you intentionally need a '
          'new exception, expand the allow-list AND open a task to '
          'migrate it off.\n\nViolations:\n${violations.join('\n')}',
    );

    // Surface allow-list size in CI logs so stale entries are visible.
    // Tests in client/test/ can use stdout directly without tripping
    // any lint (avoid_print is only enforced under lib/).
    stdout.writeln(
        '[no_bare_logging] allow-list size: ${allowList.length} (target: 0)');
  });
}
