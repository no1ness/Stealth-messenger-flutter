import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Scans the source tree for English user-visible strings that should
/// have been translated to Russian.
///
/// This is a regression gate — if a future change adds new English
/// strings without translating them, this test fails.
///
/// **Exceptions (allowed English):**
/// - `'E2E ENCRYPTED'` — brand signature element
/// - `'Web'` / `'Mobile'` — platform identifiers in insight_panel
/// - `'Browser WebRTC'`, `'Support'`, `'Secure context'`, etc. —
///   technical data-field labels in diagnostics screens
/// - `'OK'` in dialogs — universally accepted
/// - Log-level and enum constants (`'Error'`, `'Warning'` when used
///   as semantic labels, not user-visible copy)
void main() {
  test('no English user-visible strings remain in lib/ui/ and lib/themes/', () {
    final dir = Directory('lib');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) =>
            f.path.startsWith('lib${Platform.pathSeparator}ui') ||
            f.path.startsWith('lib${Platform.pathSeparator}themes'))
        .toList();

    final re = RegExp(
      r"(?<![A-Za-z])'[A-Z][a-z]{2,}\s{0,3}'",
    );

    final allowList = <RegExp>[
      RegExp(r"'E2E ENCRYPTED'"),
      RegExp(r"'Browser WebRTC'"),
      RegExp(r"'MediaDevices API'"),
      RegExp(r"'RTCPeerConnection'"),
      RegExp(r"'Accessibility'"),
      RegExp(r"'OK'"),
      RegExp(r"'Yes'"),
      RegExp(r"'No'"),
      RegExp(r"'Web'"),
      RegExp(r"'Mobile'"),
      RegExp(r"'Error'"),
      RegExp(r"'Warning'"),
      RegExp(r"'Unknown'"),
      RegExp(r"'Idle'"),
      RegExp(r"'Stopped'"),
    ];

    final issues = <String>[];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final match in re.allMatches(line)) {
          final matched = match.group(0)!;
          if (allowList.any((a) => a.hasMatch(matched))) continue;
          issues.add('${file.path}:${i + 1}: $matched');
        }
      }
    }

    if (issues.isNotEmpty) {
      fail(
        'Found ${issues.length} untranslated English string(s):\n'
        '${issues.join('\n')}',
      );
    }
  });
}
