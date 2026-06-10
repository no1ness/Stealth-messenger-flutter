import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';

void main() {
  group('pbIdFromLocalUuid', () {
    test('maps canonical UUID to deterministic 15-char PocketBase id', () {
      final pbId = pbIdFromLocalUuid('550e8400-e29b-41d4-a716-446655440000');
      expect(pbId, hasLength(15));
      expect(pbId, matches(RegExp(r'^[a-z0-9]{15}$')));
      expect(
        pbId,
        pbIdFromLocalUuid('550e8400-e29b-41d4-a716-446655440000'),
      );
    });

    test('passes valid 15-char PocketBase ids through unchanged', () {
      const id = 'abcd12345678901';
      expect(pbIdFromLocalUuid(id), id);
    });

    test('hashes non-UUID fixtures to 15 chars', () {
      final pbId = pbIdFromLocalUuid('user-A');
      expect(pbId, hasLength(15));
      expect(pbId, matches(RegExp(r'^[a-z0-9]{15}$')));
    });
  });

  group('wireIdToLocalUuid', () {
    test('resolves wire id back to a known local user id', () {
      const local = '550e8400-e29b-41d4-a716-446655440000';
      final wire = pbIdFromLocalUuid(local);
      expect(wireIdToLocalUuid(wire, [local]), local);
    });

    test('passes opaque wire ids through when unknown', () {
      expect(wireIdToLocalUuid('abcd12345678901', const []), 'abcd12345678901');
    });
  });

  group('localUuidFromPbId', () {
    test('reinserts dashes into a legacy 32-hex PocketBase id', () {
      expect(
        localUuidFromPbId('550e8400e29b41d4a716446655440000'),
        '550e8400-e29b-41d4-a716-446655440000',
      );
    });

    test('passes 15-char ids through unchanged', () {
      const id = 'abcd12345678901';
      expect(localUuidFromPbId(id), id);
    });
  });
}
