// Lightweight structured logger used across the client.
//
// Goals
// -----
//
// 1. Honour the project rule `client/.ai-factory/rules/base.md:40` —
//    "logging via `debugPrint`, never `print`".
// 2. Avoid leaking sensitive ids into logs above DEBUG level by
//    automatically redacting well-known key names (userId, pbId, email,
//    ...) down to a tail-only marker (`…1234`).
// 3. Keep call sites compact so migrating from `debugPrint('[scope] ...')`
//    is a one-liner.

import 'package:flutter/foundation.dart' show debugPrint;

enum LogLevel { debug, info, warn, error }

/// Keys in `extras` whose values are treated as sensitive identifiers.
/// At [LogLevel.info] and above the values are redacted; at
/// [LogLevel.debug] they are written verbatim for diagnosability.
const Set<String> _sensitiveKeys = <String>{
  'actualPbId',
  'callerUserId',
  'creator',
  'email',
  'expectedPbId',
  'fromUserId',
  'localUuid',
  'modelId',
  'pbCreator',
  'pbId',
  'pbSelfId',
  'pbTarget',
  'pbUserId',
  'peerId',
  'recipient',
  'selfUserId',
  'sender',
  'storedPbUserId',
  'target',
  'targetUserId',
  'userId',
};

/// Redacts an identifier to a tail-only marker. Used for any value
/// associated with a sensitive key when logging above DEBUG level.
///
/// Examples (length-based fallbacks for short test fixtures):
///   ''               → ''
///   'abc'            → '…'
///   'abcd'           → '…'
///   'abcde'          → '…bcde'
///   'abcdef'         → '…cdef'
///   '550e8400-…-0000' → '…0000'
String redactId(String? id) {
  if (id == null || id.isEmpty) return '';
  if (id.length <= 4) return '…';
  return '…${id.substring(id.length - 4)}';
}

class Logger {
  /// The minimum level that will be emitted. Mutable for tests / DEBUG
  /// switches. Default keeps DEBUG enabled — production builds should
  /// lower this to INFO via a startup hook.
  static LogLevel currentLevel = LogLevel.debug;

  static void debug(String message, {Map<String, dynamic>? extras}) =>
      _log(LogLevel.debug, message, extras);

  static void info(String message, {Map<String, dynamic>? extras}) =>
      _log(LogLevel.info, message, extras);

  static void warn(String message, {Map<String, dynamic>? extras}) =>
      _log(LogLevel.warn, message, extras);

  static void error(String message, {Map<String, dynamic>? extras}) =>
      _log(LogLevel.error, message, extras);

  static void _log(
    LogLevel level,
    String message,
    Map<String, dynamic>? extras,
  ) {
    if (level.index < currentLevel.index) return;
    final levelTag = '[${level.name.toUpperCase()}]';
    final redactSensitive = level != LogLevel.debug;
    final extrasText = _formatExtras(extras, redact: redactSensitive);
    debugPrint('$levelTag $message$extrasText');
  }

  static String _formatExtras(
    Map<String, dynamic>? extras, {
    required bool redact,
  }) {
    if (extras == null || extras.isEmpty) return '';
    final parts = <String>[];
    for (final entry in extras.entries) {
      final isSensitive = _sensitiveKeys.contains(entry.key);
      final stringValue = entry.value?.toString() ?? 'null';
      final shown =
          (redact && isSensitive) ? redactId(stringValue) : stringValue;
      parts.add('${entry.key}=$shown');
    }
    return ' ${parts.join(' ')}';
  }
}
