import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/logging/logger.dart';

void main() {
  group('redactId', () {
    test('empty input → empty output', () {
      expect(redactId(''), '');
      expect(redactId(null), '');
    });

    test('short ids collapse fully', () {
      expect(redactId('a'), '…');
      expect(redactId('abc'), '…');
      expect(redactId('abcd'), '…');
    });

    test('keeps last four characters when long enough', () {
      expect(redactId('abcde'), '…bcde');
      expect(redactId('smoke_a_1747654321'), '…4321');
      expect(
        redactId('550e8400-e29b-41d4-a716-446655440000'),
        '…0000',
      );
    });
  });

  group('Logger', () {
    final captured = <String>[];
    final originalDebugPrint = debugPrint;

    setUp(() {
      captured.clear();
      Logger.currentLevel = LogLevel.debug;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };
    });

    tearDown(() {
      // Restore stock debugPrint so other tests are unaffected.
      debugPrint = originalDebugPrint;
    });

    test('debug emits sensitive ids verbatim', () {
      Logger.debug('[signaling] connect', extras: {
        'roomId': 'room-1',
        'selfUserId': '550e8400-e29b-41d4-a716-446655440000',
      });

      expect(captured, hasLength(1));
      expect(captured.single, contains('[DEBUG] [signaling] connect'));
      expect(
        captured.single,
        contains('selfUserId=550e8400-e29b-41d4-a716-446655440000'),
      );
      expect(captured.single, contains('roomId=room-1'));
    });

    test('info redacts sensitive ids', () {
      Logger.info('[signaling] connect', extras: {
        'roomId': 'room-1',
        'selfUserId': '550e8400-e29b-41d4-a716-446655440000',
      });

      expect(captured, hasLength(1));
      expect(captured.single, contains('[INFO] [signaling] connect'));
      expect(captured.single, contains('roomId=${redactId("room-1")}'));
      expect(captured.single, contains('selfUserId=…0000'));
      expect(
        captured.single.contains('550e8400'),
        isFalse,
        reason: 'full id must not leak at INFO level',
      );
    });

    test('warn / error also redact sensitive ids', () {
      Logger.warn('[signaling] subscribe failure',
          extras: {'pbId': 'abcdef123456'});
      Logger.error('[signaling] auth mismatch',
          extras: {'userId': 'abcdef123456', 'reason': 'mismatch-xyz'});

      expect(captured, hasLength(2));
      expect(captured[0], contains('pbId=…3456'));
      expect(
        captured[1],
        allOf(
          contains('userId=…3456'),
          // `reason` is not in the sensitive set — pass through verbatim.
          contains('reason=mismatch-xyz'),
        ),
      );
    });

    test('respects currentLevel threshold', () {
      Logger.currentLevel = LogLevel.warn;
      Logger.debug('debug message');
      Logger.info('info message');
      Logger.warn('warn message');
      Logger.error('error message');

      expect(
        captured.map((s) => s.split(' ')[0]).toList(),
        const ['[WARN]', '[ERROR]'],
      );
    });

    test('omits the trailing space when extras is empty or null', () {
      Logger.info('no extras here');
      Logger.info('still no extras', extras: const <String, dynamic>{});
      expect(captured, hasLength(2));
      expect(captured[0], '[INFO] no extras here');
      expect(captured[1], '[INFO] still no extras');
    });
  });
}
