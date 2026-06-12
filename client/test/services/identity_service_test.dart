import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/identity/identity_service.dart';

/// Focused unit tests for the public surface that can be exercised
/// without a real `SharedPreferences` instance. Methods that touch
/// storage (`getUserId`, `registerUser`, `logout`) are covered by
/// existing widget/integration tests; here we just lock down the pure
/// bundle-encoding logic that task #5 of the hardening-followup plan
/// extracted from `LocalAppService`.
void main() {
  group('IdentityService.encodeOwnContactBundle', () {
    test('produces a stealth: prefixed base64url payload', () {
      final bundle = IdentityService().encodeOwnContactBundle(
        userId: '550e8400-e29b-41d4-a716-446655440000',
        nickname: 'Alice',
        publicKey: 'AAECAwQFBgcICQoLDA0ODw==',
      );
      expect(bundle, startsWith('stealth:'));
      // base64url body — no '+' / '/' / padding-with-equals.
      final body = bundle.substring('stealth:'.length);
      expect(body, isNot(contains('+')));
      expect(body, isNot(contains('/')));
    });

    test('round-trip through base64url decode yields canonical v: 1 JSON', () {
      final bundle = IdentityService().encodeOwnContactBundle(
        userId: 'user-1',
        nickname: 'Bob',
        publicKey: 'pub-1',
      );
      final encoded = bundle.substring('stealth:'.length);
      final padded = encoded.padRight(
        encoded.length + (4 - encoded.length % 4) % 4,
        '=',
      );
      final decoded = utf8.decode(base64Url.decode(padded));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      expect(json, {
        'v': 1,
        'user_id': 'user-1',
        'name': 'Bob',
        'public_key': 'pub-1',
      });
    });

    test('preserves long identifiers without truncation', () {
      final longKey = 'A' * 1024;
      final bundle = IdentityService().encodeOwnContactBundle(
        userId: 'u',
        nickname: 'n',
        publicKey: longKey,
      );
      final body = bundle.substring('stealth:'.length);
      final padded =
          body.padRight(body.length + (4 - body.length % 4) % 4, '=');
      final json = jsonDecode(utf8.decode(base64Url.decode(padded)))
          as Map<String, dynamic>;
      expect(json['public_key'], longKey);
    });
  });
}
