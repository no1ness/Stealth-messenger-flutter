import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';

void main() {
  group('pbIdFromLocalUuid', () {
    test('computes SHA-256 prefix for a canonical UUID', () {
      expect(
        pbIdFromLocalUuid('550e8400-e29b-41d4-a716-446655440000'),
        'a3a9e1ed9732cab',
      );
    });

    test('handles uppercase hex digits', () {
      expect(
        pbIdFromLocalUuid('AABBCCDD-1122-3344-5566-778899AABBCC'),
        '0b1904e0cf655ee',
      );
    });

    test('truncates long non-UUID input, keeps short unchanged', () {
      expect(pbIdFromLocalUuid('user-A'), 'user-A');
      expect(pbIdFromLocalUuid('smoke_a_1234567890123456'), 'smoke_a_1234567');
      expect(pbIdFromLocalUuid(''), '');
    });
  });

  group('PbUserIdResolver', () {
    test('resolves known PB-ids to local UUIDs', () {
      const knownUuid = '550e8400-e29b-41d4-a716-446655440000';
      final resolver = PbUserIdResolver([knownUuid]);
      final pbId = pbIdFromLocalUuid(knownUuid);
      expect(resolver.localUuidFromPbId(pbId), knownUuid);
      expect(resolver.knows(pbId), true);
    });

    test('passes unknown PB-ids through unchanged', () {
      final resolver = PbUserIdResolver([]);
      expect(resolver.localUuidFromPbId('unknown_id'), 'unknown_id');
      expect(resolver.knows('unknown_id'), false);
    });

    test('empty resolver returns passthrough for any input', () {
      final resolver = PbUserIdResolver.empty;
      expect(resolver.localUuidFromPbId('some_pb_id'), 'some_pb_id');
    });

    test('resolves multiple UUIDs efficiently', () {
      final resolver = PbUserIdResolver([
        '550e8400-e29b-41d4-a716-446655440000',
        'AABBCCDD-1122-3344-5566-778899AABBCC',
      ]);
      expect(
        resolver.localUuidFromPbId('a3a9e1ed9732cab'),
        '550e8400-e29b-41d4-a716-446655440000',
      );
      expect(
        resolver.localUuidFromPbId('0b1904e0cf655ee'),
        'AABBCCDD-1122-3344-5566-778899AABBCC',
      );
    });
  });

  group('kPbIdLength', () {
    test('SHA-256 prefix is exactly 15 chars', () {
      expect(kPbIdLength, 15);
      final pbId = pbIdFromLocalUuid('550e8400-e29b-41d4-a716-446655440000');
      expect(pbId.length, kPbIdLength);
    });
  });
}
