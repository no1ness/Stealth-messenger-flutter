import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/diagnostics/log_scrubber.dart';

void main() {
  group('scrubInlineSensitive', () {
    test('empty input returns empty', () {
      expect(scrubInlineSensitive(''), '');
    });

    test('UUID inline is redacted to tail-only marker', () {
      const line = 'chat 550e8400-e29b-41d4-a716-446655440000 failed';
      expect(scrubInlineSensitive(line), 'chat …0000 failed');
    });

    test('multiple UUIDs on the same line are all redacted', () {
      const line = 'from=00000000-0000-0000-0000-000000000001 to='
          '11111111-1111-1111-1111-111111111111';
      expect(scrubInlineSensitive(line), 'from=…0001 to=…1111');
    });

    test('15-char PocketBase id with mixed digits+letters is redacted', () {
      // Realistic PB id (15 lowercase alphanumeric).
      const line = '[signaling] pb record abc123def456789 dropped';
      expect(scrubInlineSensitive(line),
          '[signaling] pb record …6789 dropped');
    });

    test('all-letter 15-char word is NOT redacted (heuristic)', () {
      // "notifications" is 13, padding to 15 with letters only.
      const line = 'reconnect reconnectingxx queue depth=3';
      // 'reconnectingxx' is 14, so no 15-char word; verify safety on 15.
      const safe = 'aaaaaaaaaaaaaaa is fifteen letters';
      expect(scrubInlineSensitive(line), line);
      expect(scrubInlineSensitive(safe), safe);
    });

    test('all-digit 15-char number is NOT redacted (heuristic)', () {
      const line = 'counter=123456789012345 elapsed';
      expect(scrubInlineSensitive(line), line);
    });

    test('base64 ed25519 public key is redacted', () {
      // 43-char base64 (no padding) → real X25519 pub key shape.
      const line = 'peer pubKey=Abc123XyzDEF456pqr789StuVWX098mnoPQR0aBcDef';
      final scrubbed = scrubInlineSensitive(line);
      expect(scrubbed, contains('peer pubKey=…'));
      expect(scrubbed, isNot(contains('Abc123XyzDEF456')));
    });

    test('common long words are NOT redacted as base64 keys (heuristic)',
        () {
      // Long natural-language word lacking digits — must NOT match.
      const line =
          'configurationValidationStrategyHelper passed all phases now';
      expect(scrubInlineSensitive(line), line);
    });

    test('idempotent: scrub(scrub(x)) == scrub(x)', () {
      const line = 'user 550e8400-e29b-41d4-a716-446655440000 / pb '
          'abc123def456789';
      final once = scrubInlineSensitive(line);
      final twice = scrubInlineSensitive(once);
      expect(twice, once);
    });

    test('does not touch the redaction marker itself', () {
      // The replacement marker should not be re-matched by any pattern.
      const marker = 'user …0000 pinged';
      expect(scrubInlineSensitive(marker), marker);
    });
  });
}
