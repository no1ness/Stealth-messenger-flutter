import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final AesGcm _aes = AesGcm.with256bits();

/// Encrypts [bytes] with [secretKey] using AES-GCM-256 and returns a
/// base64 string of `nonce || ciphertext || mac`. The nonce is randomly
/// generated per call; the 16-byte tag is appended so [decryptBytesWithSecret]
/// can recover everything from a single string.
///
/// Used by:
///   - per-message 1:1 encryption (MessageService)
///   - per-group symmetric encryption (LocalAppService group helpers)
///   - attachment payload encryption (LocalAppService attachment helpers)
///
/// Extracted as a top-level helper in task #6 of the hardening-followup
/// plan to avoid duplicating the same code across three services.
Future<String> encryptBytesWithSecret(
  Uint8List bytes,
  SecretKey secretKey,
) async {
  final secretBox = await _aes.encrypt(bytes, secretKey: secretKey);
  final combined = Uint8List(
    secretBox.nonce.length +
        secretBox.cipherText.length +
        secretBox.mac.bytes.length,
  );
  combined.setRange(0, secretBox.nonce.length, secretBox.nonce);
  combined.setRange(
    secretBox.nonce.length,
    secretBox.nonce.length + secretBox.cipherText.length,
    secretBox.cipherText,
  );
  combined.setRange(
    secretBox.nonce.length + secretBox.cipherText.length,
    combined.length,
    secretBox.mac.bytes,
  );
  return base64Encode(combined);
}

/// Inverse of [encryptBytesWithSecret] — decodes the base64 payload,
/// splits it back into nonce / ciphertext / mac, and verifies the AES-GCM
/// authentication tag. Throws on any tampering / wrong key.
Future<Uint8List> decryptBytesWithSecret(
  String payload,
  SecretKey secretKey,
) async {
  final combined = base64Decode(payload);
  const nonceLength = 12;
  const macLength = 16;
  final nonce = combined.sublist(0, nonceLength);
  final mac = Mac(combined.sublist(combined.length - macLength));
  final cipherText = combined.sublist(
    nonceLength,
    combined.length - macLength,
  );
  final clearText = await _aes.decrypt(
    SecretBox(cipherText, nonce: nonce, mac: mac),
    secretKey: secretKey,
  );
  return Uint8List.fromList(clearText);
}
