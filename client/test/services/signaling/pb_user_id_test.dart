import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';

void main() {
  group('pbIdFromLocalUuid', () {
    test('strips dashes from a canonical UUID v4', () {
      expect(
        pbIdFromLocalUuid('550e8400-e29b-41d4-a716-446655440000'),
        '550e8400e29b41d4a716446655440000',
      );
    });

    test('handles uppercase hex digits', () {
      expect(
        pbIdFromLocalUuid('AABBCCDD-1122-3344-5566-778899AABBCC'),
        'AABBCCDD112233445566778899AABBCC',
      );
    });

    test('passes non-UUID input through unchanged (test fixture id)', () {
      expect(pbIdFromLocalUuid('user-A'), 'user-A');
      expect(pbIdFromLocalUuid('smoke_a_1234567890123456'),
          'smoke_a_1234567890123456');
      expect(pbIdFromLocalUuid(''), '');
    });

    test('passes already-stripped UUIDs through unchanged', () {
      expect(
        pbIdFromLocalUuid('550e8400e29b41d4a716446655440000'),
        '550e8400e29b41d4a716446655440000',
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
    test('canonical UUID survives strip→insert', () {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      expect(localUuidFromPbId(pbIdFromLocalUuid(uuid)), uuid);
    });

    test('non-UUID survives both directions', () {
      const id = 'smoke_a_1234567890123456';
      expect(pbIdFromLocalUuid(id), id);
      expect(localUuidFromPbId(id), id);
    });
  });
}
