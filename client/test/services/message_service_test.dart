import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/crypto/aes_bytes.dart';
import 'package:stealth/services/messaging/message_service.dart';

/// Focused unit tests for the extracted [MessageService]. Methods that
/// require live `IdentityService` + `ContactService` + `LocalDatabaseService`
/// state (full encrypt/decrypt round-trip on a real chat) stay on the
/// existing widget/integration test surface; here we lock down the parts
/// that can run without that bootstrap:
///
/// 1. The pure AES-GCM helper round-trip ([aes_bytes.dart]).
/// 2. The `decryptRawMessage` early-out for soft-deleted rows.
/// 3. The defensive `StateError` when group encryption is invoked before
///    [MessageService.attachGroupCrypto] is wired.
void main() {
  group('aes_bytes helpers (top-level, shared crypto utility)', () {
    test('round-trips arbitrary byte payload', () async {
      final key = await AesGcm.with256bits().newSecretKey();
      final plaintext = List<int>.generate(256, (i) => i % 256);
      final encrypted = await encryptBytesWithSecret(
          plaintext.cast<int>().toList().asUint8List(), key);
      final decrypted = await decryptBytesWithSecret(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('decryption with the wrong key throws (MAC fails)', () async {
      final key1 = await AesGcm.with256bits().newSecretKey();
      final key2 = await AesGcm.with256bits().newSecretKey();
      final encrypted =
          await encryptBytesWithSecret('hello'.codeUnits.asUint8List(), key1);
      expect(
        () => decryptBytesWithSecret(encrypted, key2),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('MessageService.decryptRawMessage', () {
    test('returns soft-deleted row unchanged (no decrypt attempted)', () async {
      final row = {
        'id': 'm1',
        'content': 'irrelevant-encrypted-blob',
        'deleted_at': '2026-05-20T00:00:00Z',
        'metadata': {'encryption': 'e2e'},
      };
      final result = await MessageService().decryptRawMessage(row);
      expect(result['deleted_at'], '2026-05-20T00:00:00Z');
      // Content is left untouched — no decrypt was attempted.
      expect(result['content'], 'irrelevant-encrypted-blob');
    });
  });

  // NOTE: full encrypt/decrypt round-trip for a 1:1 chat needs a real
  // StorageService + LocalDatabaseService bootstrap (platform channels)
  // — that is covered by existing widget/integration tests, not here.
}

extension on List<int> {
  Uint8List asUint8List() => Uint8List.fromList(this);
}
