import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/contacts/contact_service.dart';
import 'package:stealth/services/identity/identity_service.dart';

/// Focused unit tests for the pure `decodeContactBundle` helper. Stateful
/// methods on `ContactService` (search, addContact) need a real DB and
/// are exercised through existing widget/integration tests; here we lock
/// down the bundle-parsing contract task #5 inherited from
/// `LocalAppService._decodeContactBundle`.
///
/// Acceptance from the plan: v1 happy path + at least 3 rejection cases
/// (bad b64, missing public_key, wrong version).
void main() {
  String bundleFor(Map<String, dynamic> payload) =>
      'stealth:${base64UrlEncode(utf8.encode(jsonEncode(payload)))}';

  group('decodeContactBundle — happy path', () {
    test('round-trips through IdentityService.encodeOwnContactBundle', () {
      final encoded = IdentityService().encodeOwnContactBundle(
        userId: 'u-1',
        nickname: 'Alice',
        publicKey: 'pk-1',
      );
      final decoded = decodeContactBundle(encoded);
      expect(decoded, isNotNull);
      expect(decoded!['user_id'], 'u-1');
      expect(decoded['contact_user_id'], 'u-1');
      expect(decoded['name'], 'Alice');
      expect(decoded['nickname'], 'Alice');
      expect(decoded['public_key'], 'pk-1');
    });

    test('accepts unpadded base64url (handles `_normalizeBase64Url`)', () {
      // Hand-craft payload of length that produces unpadded base64 (no
      // trailing `=`). The decoder must pad internally.
      final json = jsonEncode({
        'v': 1,
        'user_id': 'ab',
        'name': 'cd',
        'public_key': 'ef',
      });
      var b64 = base64UrlEncode(utf8.encode(json));
      // Strip any trailing '=' that base64UrlEncode might emit.
      b64 = b64.replaceAll(RegExp(r'=+$'), '');
      final decoded = decodeContactBundle('stealth:$b64');
      expect(decoded, isNotNull);
      expect(decoded!['user_id'], 'ab');
    });
  });

  group('decodeContactBundle — rejections', () {
    test('returns null when prefix is missing', () {
      // No `stealth:` prefix → bail before any parsing.
      final raw = bundleFor({
        'v': 1,
        'user_id': 'u',
        'public_key': 'pk',
      }).substring('stealth:'.length);
      expect(decodeContactBundle(raw), isNull);
    });

    test('returns null for bad base64', () {
      expect(decodeContactBundle('stealth:!!!not-base64!!!'), isNull);
    });

    test('returns null when public_key is missing', () {
      final bundle = bundleFor({
        'v': 1,
        'user_id': 'u',
        'name': 'Alice',
        // intentionally no public_key
      });
      expect(decodeContactBundle(bundle), isNull);
    });

    test('returns null when public_key is empty', () {
      final bundle = bundleFor({
        'v': 1,
        'user_id': 'u',
        'name': 'Alice',
        'public_key': '',
      });
      expect(decodeContactBundle(bundle), isNull);
    });

    test('returns null when user_id is missing', () {
      final bundle = bundleFor({
        'v': 1,
        'name': 'Alice',
        'public_key': 'pk',
      });
      expect(decodeContactBundle(bundle), isNull);
    });

    test('returns null for unsupported version', () {
      final bundle = bundleFor({
        'v': 2,
        'user_id': 'u',
        'name': 'Alice',
        'public_key': 'pk',
      });
      expect(decodeContactBundle(bundle), isNull);
    });
  });

  group('decodeContactBundle — defaulting', () {
    test('falls back to user_id when name is absent', () {
      final bundle = bundleFor({
        'v': 1,
        'user_id': 'just-an-id',
        'public_key': 'pk',
      });
      final decoded = decodeContactBundle(bundle)!;
      expect(decoded['name'], 'just-an-id');
      expect(decoded['nickname'], 'just-an-id');
    });
  });
}
