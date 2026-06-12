import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';

void main() {
  group('pbIdFromLocalUuid', () {
    test('strips dashes and truncates canonical UUID to 15 chars', () {
      expect(
        pbIdFromLocalUuid('550e8400-e29b-41d4-a716-446655440000'),
        '550e8400e29b41d',
      );
    });

    test('handles uppercase hex digits with truncation', () {
      expect(
        pbIdFromLocalUuid('AABBCCDD-1122-3344-5566-778899AABBCC'),
        'AABBCCDD1122334',
      );
    });

    test('truncates long non-UUID input, keeps short unchanged', () {
      expect(pbIdFromLocalUuid('user-A'), 'user-A');
      expect(pbIdFromLocalUuid('smoke_a_1234567890123456'), 'smoke_a_1234567');
      expect(pbIdFromLocalUuid(''), '');
    });

    test('truncates already-stripped UUID to 15 chars', () {
      expect(
        pbIdFromLocalUuid('550e8400e29b41d4a716446655440000'),
        '550e8400e29b41d',
      );
    });
  });

  group('localUuidFromPbId', () {
    test('reinserts dashes into a 32-hex PocketBase id', () {
      expect(
        localUuidFromPbId('550e8400e29b41d4a716446655440000'),
        '550e8400-e29b-41d4-a716-446655440000',
      );
    });

    test('passes non-32-hex input through unchanged', () {
      expect(localUuidFromPbId('user-A'), 'user-A');
      expect(localUuidFromPbId('smoke_a_1234567890123456'),
          'smoke_a_1234567890123456');
      expect(localUuidFromPbId(''), '');
    });

    test('passes canonical-UUID-shaped input through unchanged', () {
      expect(
        localUuidFromPbId('550e8400-e29b-41d4-a716-446655440000'),
        '550e8400-e29b-41d4-a716-446655440000',
      );
    });
  });

  group('round-trip', () {
    test('canonical UUID truncated to 15 chars — no longer reversible', () {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      expect(localUuidFromPbId(pbIdFromLocalUuid(uuid)), '550e8400e29b41d');
    });

    test('long non-UUID truncated in pb→local direction', () {
      const id = 'smoke_a_1234567890123456';
      expect(pbIdFromLocalUuid(id), 'smoke_a_1234567');
      expect(localUuidFromPbId('smoke_a_1234567'), 'smoke_a_1234567');
    });
  });
}
