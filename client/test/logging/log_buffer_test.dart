import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/logging/log_buffer.dart';
import 'package:stealth/logging/logger.dart';

void main() {
  // Isolate buffer state from other tests in the suite — Logger and
  // LogBuffer are global singletons.
  setUp(() {
    LogBuffer.instance.clearForTests();
    // Console-verbosity must NOT affect what reaches the buffer; keep
    // a sensible default so tests below can switch it freely.
    Logger.currentLevel = LogLevel.debug;
  });

  group('LogEntry', () {
    test('formattedLine assembles "[LEVEL] message extras"', () {
      final entry = LogEntry(
        level: LogLevel.warn,
        timestampUtc: DateTime.utc(2026, 5, 22, 17, 30, 14),
        message: 'reconnect attempt',
        extrasText: ' chatId=…a91f attempt=3',
      );
      expect(entry.formattedLine,
          '[WARN] reconnect attempt chatId=…a91f attempt=3');
    });

    test('formattedLine with null extrasText omits suffix', () {
      final entry = LogEntry(
        level: LogLevel.error,
        timestampUtc: DateTime.utc(2026, 5, 22),
        message: 'ICE failed',
      );
      expect(entry.formattedLine, '[ERROR] ICE failed');
    });
  });

  group('LogBuffer', () {
    test('appends below capacity, snapshot newest-first', () {
      final buffer = LogBuffer.instance;
      buffer.append(_entry(LogLevel.warn, 'a', 1));
      buffer.append(_entry(LogLevel.warn, 'b', 2));
      buffer.append(_entry(LogLevel.warn, 'c', 3));

      final snap = buffer.snapshot(min: LogLevel.debug);
      expect(snap.map((e) => e.message).toList(), ['c', 'b', 'a']);
    });

    test('FIFO eviction when capacity is exceeded', () {
      final buffer = LogBuffer.instance;
      for (var i = 0; i < LogBuffer.capacity + 50; i++) {
        buffer.append(_entry(LogLevel.warn, 'm$i', i));
      }
      final snap = buffer.snapshot(min: LogLevel.debug);
      expect(snap.length, LogBuffer.capacity);
      // Newest first → m{capacity+49} is the head; the oldest survivor
      // is m50 (m0..m49 were evicted).
      expect(snap.first.message, 'm${LogBuffer.capacity + 49}');
      expect(snap.last.message, 'm50');
    });

    test('snapshot(min) filters lower levels', () {
      final buffer = LogBuffer.instance;
      buffer.append(_entry(LogLevel.debug, 'd', 1));
      buffer.append(_entry(LogLevel.info, 'i', 2));
      buffer.append(_entry(LogLevel.warn, 'w', 3));
      buffer.append(_entry(LogLevel.error, 'e', 4));

      final warns = buffer.snapshot(min: LogLevel.warn);
      expect(warns.map((e) => e.level).toList(),
          [LogLevel.error, LogLevel.warn]);
    });

    test('snapshot(limit) trims after filtering', () {
      final buffer = LogBuffer.instance;
      for (var i = 0; i < 10; i++) {
        buffer.append(_entry(LogLevel.warn, 'w$i', i));
      }
      final trimmed = buffer.snapshot(min: LogLevel.debug, limit: 3);
      expect(trimmed.length, 3);
      // Newest three first.
      expect(trimmed.map((e) => e.message).toList(), ['w9', 'w8', 'w7']);
    });

    test('snapshot returns unmodifiable list', () {
      final buffer = LogBuffer.instance;
      buffer.append(_entry(LogLevel.warn, 'a', 1));
      final snap = buffer.snapshot();
      expect(() => snap.add(_entry(LogLevel.warn, 'b', 2)),
          throwsUnsupportedError);
    });
  });

  group('Logger -> LogBuffer integration', () {
    test('WARN/ERROR reach buffer even when currentLevel hides them',
        () {
      Logger.currentLevel = LogLevel.error;
      Logger.warn('hidden on console but buffered');
      Logger.error('also buffered');

      final snap = Logger.snapshot(min: LogLevel.warn);
      expect(snap.length, 2);
      expect(snap.first.level, LogLevel.error);
      expect(snap.last.level, LogLevel.warn);
    });

    test('DEBUG entry reaches buffer even when console is set to WARN', () {
      // Buffer captures regardless of currentLevel; only debugPrint is
      // gated. snapshot(min: debug) must still see the entry.
      Logger.currentLevel = LogLevel.warn;
      Logger.debug('diagnostic detail');

      final snap = Logger.snapshot(min: LogLevel.debug);
      expect(snap, hasLength(1));
      expect(snap.first.message, 'diagnostic detail');
      expect(snap.first.level, LogLevel.debug);
    });

    test('extras with sensitive key are redacted in extrasText', () {
      Logger.warn('reconnect',
          extras: {'userId': '550e8400-e29b-41d4-a716-446655440000'});
      final snap = Logger.snapshot(min: LogLevel.warn);
      expect(snap, hasLength(1));
      expect(snap.first.extrasText, ' userId=…0000');
      expect(snap.first.message, 'reconnect');
    });

    test('async appends in sequence are preserved', () async {
      Future<void> writeOne(int i) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        Logger.warn('async$i');
      }

      await Future.wait([writeOne(1), writeOne(2), writeOne(3)]);
      final snap = Logger.snapshot(min: LogLevel.warn);
      expect(snap.length, 3);
      expect(snap.map((e) => e.message).toSet(),
          {'async1', 'async2', 'async3'});
    });
  });
}

LogEntry _entry(LogLevel level, String message, int second) => LogEntry(
      level: level,
      timestampUtc: DateTime.utc(2026, 1, 1, 0, 0, second),
      message: message,
    );
