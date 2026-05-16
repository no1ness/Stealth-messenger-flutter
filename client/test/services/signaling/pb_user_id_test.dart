import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';

void main() {
  group('pbIdFromLocalUuid', () {
    test('canonical UUID hashes to a deterministic 15-char id', () {
      // Hash is SHA-256 prefix; the value below was computed once and
      // pinned to detect accidental algorithm changes.
      expect(
        pbIdFromLocalUuid('550e8400-e29b-41d4-a716-446655440000'),
        'a3a9e1ed9732cab',
      );
    });

    test('id is exactly 15 chars (PocketBase requirement)', () {
      const samples = [
        '550e8400-e29b-41d4-a716-446655440000',
        'AABBCCDD-1122-3344-5566-778899AABBCC',
        '00000000-0000-0000-0000-000000000000',
      ];
      for (final uuid in samples) {
        expect(pbIdFromLocalUuid(uuid).length, kPbIdLength,
            reason: 'uuid=$uuid');
      }
    });

    test('uppercase and lowercase UUID hash to different ids', () {
      // SHA-256 of the literal string differs by case — UUIDs in the app
      // are always lowercase, so this just documents non-canonicalisation.
      expect(
        pbIdFromLocalUuid('AABBCCDD-1122-3344-5566-778899AABBCC'),
        isNot(pbIdFromLocalUuid('aabbccdd-1122-3344-5566-778899aabbcc')),
      );
    });

    test('passes non-UUID input through unchanged (test fixture ids)', () {
      expect(pbIdFromLocalUuid('user-A'), 'user-A');
      expect(pbIdFromLocalUuid('smoke_a_1234567890123456'),
          'smoke_a_1234567890123456');
      expect(pbIdFromLocalUuid(''), '');
    });

    test('stripped (no-dash) UUID is treated as non-canonical and passes through',
        () {
      // The previous implementation transformed dashed↔stripped; the new
      // hash-based one does NOT, because the lossy mapping no longer fits
      // in 15 chars. A 32-hex string with no dashes is therefore a regular
      // opaque id and is returned untouched.
      expect(
        pbIdFromLocalUuid('550e8400e29b41d4a716446655440000'),
        '550e8400e29b41d4a716446655440000',
      );
    });
  });

  group('PbUserIdResolver', () {
    test('resolves a known UUID back from its hashed pbId', () {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      final resolver = PbUserIdResolver([uuid]);
      expect(resolver.localUuidFromPbId(pbIdFromLocalUuid(uuid)), uuid);
      expect(resolver.knows(pbIdFromLocalUuid(uuid)), isTrue);
    });

    test('returns input unchanged for unknown pbIds (passthrough fallback)', () {
      final resolver = PbUserIdResolver(const []);
      expect(resolver.localUuidFromPbId('unknown-id'), 'unknown-id');
      expect(resolver.knows('unknown-id'), isFalse);
    });

    test('non-UUID inputs in the known set do not poison the map', () {
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      final resolver = PbUserIdResolver([uuid, 'user-A', 'smoke_b_xyz']);
      expect(resolver.localUuidFromPbId(pbIdFromLocalUuid(uuid)), uuid);
      // Non-UUID fixtures are not hashed — the resolver simply ignores
      // them. Lookup of 'user-A' is a passthrough.
      expect(resolver.localUuidFromPbId('user-A'), 'user-A');
    });

    test('PbUserIdResolver.empty is a valid no-op', () {
      expect(PbUserIdResolver.empty.localUuidFromPbId('xyz'), 'xyz');
      expect(PbUserIdResolver.empty.knows('xyz'), isFalse);
    });

    test('round-trip for canonical UUIDs', () {
      const samples = [
        '550e8400-e29b-41d4-a716-446655440000',
        'aabbccdd-1122-3344-5566-778899aabbcc',
        '00000000-0000-0000-0000-000000000000',
      ];
      final resolver = PbUserIdResolver(samples);
      for (final uuid in samples) {
        expect(resolver.localUuidFromPbId(pbIdFromLocalUuid(uuid)), uuid);
      }
    });
  });
}
