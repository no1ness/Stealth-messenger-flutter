// Lightweight structured logger used across the client.
//
// Goals
// -----
//
// 1. Honour the project rule `.ai-factory/rules/base.md:40` — all logging
//    in `client/lib` goes through `Logger.*`, never bare `debugPrint`
//    or `print`. Enforced by `client/test/security/no_bare_logging_test.dart`.
// 2. Avoid leaking sensitive ids into logs above DEBUG level by
//    automatically redacting well-known key names (userId, pbId, email,
//    ...) down to a tail-only marker (`…1234`).
// 3. Keep call sites compact so migrating from `debugPrint('[scope] ...')`
//    is a one-liner.
// 4. Allow release/profile builds to opt into DEBUG logs without code
//    edits via `--dart-define=STEALTH_LOG_LEVEL=debug|info|warn|error`.

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

enum LogLevel { debug, info, warn, error }

/// Keys in `extras` whose values are treated as sensitive identifiers.
/// At [LogLevel.info] and above the values are redacted; at
/// [LogLevel.debug] they are written verbatim for diagnosability.
const Set<String> _sensitiveKeys = <String>{
  'actualPbId',
  'callerUserId',
  'chatId',
  'creator',
  'email',
  'expectedPbId',
  'fromUserId',
  'localUuid',
  'modelId',
  'messageId',
  'pbCreator',
  'pbId',
  'pbSelfId',
  'pbTarget',
  'pbUserId',
  'peerId',
  'recipient',
  'selfUserId',
  'sender',
  'roomId',
  'storedChatId',
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

/// Parses a case-insensitive `LogLevel` name. Returns `null` for any
/// unrecognised value (including empty string), letting the caller fall
/// back to its default. Pure function — exposed so tests can verify the
/// dart-define parsing without touching `String.fromEnvironment`.
LogLevel? parseLogLevel(String? value) {
  if (value == null) return null;
  switch (value.trim().toLowerCase()) {
    case 'debug':
      return LogLevel.debug;
    case 'info':
      return LogLevel.info;
    case 'warn':
      return LogLevel.warn;
    case 'error':
      return LogLevel.error;
    default:
      return null;
  }
}

const String _logLevelOverride =
    String.fromEnvironment('STEALTH_LOG_LEVEL', defaultValue: '');

class Logger {
  /// The minimum level that will be emitted. Resolution order:
  ///   1. `--dart-define=STEALTH_LOG_LEVEL=debug|info|warn|error` (highest)
  ///   2. `kDebugMode` — debug builds keep DEBUG, release/profile fall to INFO.
  /// Still mutable from tests / runtime toggles.
  static LogLevel currentLevel = parseLogLevel(_logLevelOverride) ??
      (kDebugMode ? LogLevel.debug : LogLevel.info);

  /// Emits a one-shot banner with the resolved level + whether the
  /// dart-define override was set. Call once from `main.dart` after
  /// the app is up enough for `debugPrint` output to reach the console.
  static void logInitialState() {
    Logger.info('[logging] level set', extras: {
      'level': currentLevel.name,
      'override': _logLevelOverride.isEmpty ? 'unset' : _logLevelOverride,
    });
  }

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
