import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/helpers/crypto_helper.dart';

void main() {
  group('CryptoHelper.generateSymmetricKey', () {
    test('returns a 32-byte AES-256 key', () async {
      final key = await CryptoHelper.generateSymmetricKey();
      final bytes = await CryptoHelper.exportKey(key);
      expect(bytes.length, 32,
          reason: 'AesGcm.with256bits() must yield 256-bit keys.');
    });

    test('two consecutive calls return different keys', () async {
      final a = await CryptoHelper.exportKey(
        await CryptoHelper.generateSymmetricKey(),
      );
      final b = await CryptoHelper.exportKey(
        await CryptoHelper.generateSymmetricKey(),
      );
      expect(a, isNot(equals(b)),
          reason: 'generateSymmetricKey must be non-deterministic.');
    });
  });

  group('CryptoHelper.encryptData / decryptData roundtrip', () {
    late SecretKey key;

    setUp(() async {
      key = await CryptoHelper.generateSymmetricKey();
    });

    test('empty string roundtrip preserves the payload', () async {
      final ciphertext = await CryptoHelper.encryptData('', key);
      final plain = await CryptoHelper.decryptData(ciphertext, key);
      expect(plain, '');
    });

    test('short UTF-8 string roundtrip preserves the payload', () async {
      const original = 'Hello, мир! 🌍';
      final ciphertext = await CryptoHelper.encryptData(original, key);
      expect(ciphertext, isNot(equals(original)),
          reason: 'ciphertext must differ from plaintext.');
      final plain = await CryptoHelper.decryptData(ciphertext, key);
      expect(plain, original);
    });

    test('large payload (>=64 KiB) roundtrip preserves bytes', () async {
      final original = 'a' * (64 * 1024);
      final ciphertext = await CryptoHelper.encryptData(original, key);
      final plain = await CryptoHelper.decryptData(ciphertext, key);
      expect(plain.length, original.length);
      expect(plain, original);
    });

    test('two encryptions of the same plaintext have different nonces',
        () async {
      final first = await CryptoHelper.encryptData('same', key);
      final second = await CryptoHelper.encryptData('same', key);
      expect(first, isNot(equals(second)),
          reason: 'AES-GCM must generate a fresh nonce each call.');
    });

    test('decryptData throws when the ciphertext is tampered with', () async {
      final ciphertext = await CryptoHelper.encryptData('hello', key);
      // Flip one bit somewhere past the nonce + before the tag — this
      // must fail authentication, never silently decrypt.
      final raw = base64Decode(ciphertext);
      final tampered = Uint8List.fromList(raw);
      // Flip a bit in the middle of the ciphertext region.
      tampered[tampered.length ~/ 2] ^= 0x01;
      final tamperedB64 = base64Encode(tampered);

      expect(
        () => CryptoHelper.decryptData(tamperedB64, key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('decryptData throws on wrong key', () async {
      final ciphertext = await CryptoHelper.encryptData('hello', key);
      final otherKey = await CryptoHelper.generateSymmetricKey();
      expect(
        () => CryptoHelper.decryptData(ciphertext, otherKey),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('CryptoHelper.encryptJson / decryptJson roundtrip', () {
    test('encrypts and decrypts a nested map structure', () async {
      final key = await CryptoHelper.generateSymmetricKey();
      final original = <String, dynamic>{
        'kind': 'message',
        'count': 42,
        'flags': [true, false, true],
        'nested': <String, dynamic>{
          'created_at': '2026-01-01T00:00:00Z',
          'text': 'привет',
        },
      };
      final ciphertext = await CryptoHelper.encryptJson(original, key);
      final decoded = await CryptoHelper.decryptJson(ciphertext, key);
      expect(decoded, equals(original));
    });
  });

  group('CryptoHelper.deriveKeyFromSeed', () {
    test('is deterministic for the same seed', () async {
      final seed = Uint8List.fromList(
        List<int>.generate(32, (index) => index),
      );
      final keyA = await CryptoHelper.deriveKeyFromSeed(seed);
      final keyB = await CryptoHelper.deriveKeyFromSeed(seed);
      expect(await keyA.extractBytes(), equals(await keyB.extractBytes()));
    });

    test('different seeds produce different keys', () async {
      final keyA = await CryptoHelper.deriveKeyFromSeed(
        Uint8List.fromList(List<int>.generate(32, (i) => i)),
      );
      final keyB = await CryptoHelper.deriveKeyFromSeed(
        Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
      );
      expect(
        await keyA.extractBytes(),
        isNot(equals(await keyB.extractBytes())),
      );
    });
  });

  group('CryptoHelper.exportKey / importKey roundtrip', () {
    test('round-trip preserves the byte sequence', () async {
      final key = await CryptoHelper.generateSymmetricKey();
      final bytes = await CryptoHelper.exportKey(key);
      final restored = await CryptoHelper.importKey(bytes);
      expect(await restored.extractBytes(), equals(bytes));
    });

    test('a restored key decrypts a payload encrypted with the original',
        () async {
      final original = await CryptoHelper.generateSymmetricKey();
      final bytes = await CryptoHelper.exportKey(original);
      final ciphertext = await CryptoHelper.encryptData('roundtrip', original);

      final restored = await CryptoHelper.importKey(bytes);
      final plain = await CryptoHelper.decryptData(ciphertext, restored);
      expect(plain, 'roundtrip');
    });
  });
}
