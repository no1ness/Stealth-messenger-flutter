// In-memory ring buffer for recent log records.
//
// Backs [Logger.snapshot] so the in-app diagnostics screen can show the
// last N entries without depending on debugPrint capture or external sinks.
//
// Design notes:
// * The buffer writes BEFORE Logger's currentLevel guard, so WARN/ERROR
//   reach snapshots even when the console is set to a higher minimum.
// * Each entry stores structured fields (level / timestamp / message /
//   extras text) so the UI can render level, time, and body separately
//   without parsing a pre-formatted line. The composer (diagnostics
//   report) still consumes `formattedLine` for plain-text export.
// * Single Dart isolate => no synchronization primitives are needed.

import 'logger.dart';

/// One captured log record.
class LogEntry {
  const LogEntry({
    required this.level,
    required this.timestampUtc,
    required this.message,
    this.extrasText,
  });

  final LogLevel level;
  final DateTime timestampUtc;

  /// Raw message text without the `[LEVEL]` prefix.
  final String message;

  /// Pre-formatted `' key=value key2=value2'` suffix (matches the format
  /// Logger emits on the console). `null` means no extras were attached
  /// to the call site.
  final String? extrasText;

  /// Re-assembled console line. Used by the diagnostics report composer.
  String get formattedLine =>
      '[${level.name.toUpperCase()}] $message${extrasText ?? ''}';
}

/// FIFO ring buffer (capacity 500) accessed through [LogBuffer.instance].
class LogBuffer {
  LogBuffer._();

  static final LogBuffer instance = LogBuffer._();

  /// Capacity is intentionally compile-time constant — sized so that a
  /// busy session keeps ~10 minutes of WARN/ERROR plus chatty DEBUG
  /// without unbounded memory growth (~75 KB worst case at 150 B/line).
  static const int capacity = 500;

  final List<LogEntry?> _ring = List<LogEntry?>.filled(capacity, null);
  int _writeIndex = 0;
  int _filled = 0;

  /// Append a new entry, evicting the oldest if the ring is full.
  void append(LogEntry entry) {
    _ring[_writeIndex] = entry;
    _writeIndex = (_writeIndex + 1) % capacity;
    if (_filled < capacity) _filled++;
  }

  /// Newest-first snapshot filtered by [min] level and trimmed to [limit].
  /// Returns an unmodifiable list — callers cannot mutate buffer state.
  List<LogEntry> snapshot({
    LogLevel min = LogLevel.warn,
    int? limit,
  }) {
    final result = <LogEntry>[];
    // Walk backwards from the most recent write so the result is
    // already in newest-first order without an extra sort pass.
    for (var step = 1; step <= _filled; step++) {
      final index = (_writeIndex - step + capacity) % capacity;
      final entry = _ring[index];
      if (entry == null) continue;
      if (entry.level.index < min.index) continue;
      result.add(entry);
      if (limit != null && result.length >= limit) break;
    }
    return List<LogEntry>.unmodifiable(result);
  }

  /// Test-only reset. Production code never clears the buffer.
  void clearForTests() {
    for (var i = 0; i < capacity; i++) {
      _ring[i] = null;
    }
    _writeIndex = 0;
    _filled = 0;
  }
}
