import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoHelper {
  static final AesGcm _aes = AesGcm.with256bits();

  static Future<SecretKey> generateSymmetricKey() async {
    return await _aes.newSecretKey();
  }

  static Future<Uint8List> exportKey(SecretKey key) async {
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }

  static Future<SecretKey> importKey(Uint8List bytes) async {
    return SecretKey(bytes);
  }

  static Future<String> encryptData(String data, SecretKey key) async {
    final secretBox = await _aes.encrypt(
      utf8.encode(data),
      secretKey: key,
    );
    return base64Encode(secretBox.concatenation());
  }

  static Future<String> decryptData(
      String encryptedBase64, SecretKey key) async {
    final concatenation = base64Decode(encryptedBase64);
    final secretBox = SecretBox.fromConcatenation(
      concatenation,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final clearBytes = await _aes.decrypt(
      secretBox,
      secretKey: key,
    );
    return utf8.decode(clearBytes);
  }

  static Future<String> encryptJson(
      Map<String, dynamic> data, SecretKey key) async {
    return encryptData(jsonEncode(data), key);
  }

  static Future<Map<String, dynamic>> decryptJson(
      String encryptedBase64, SecretKey key) async {
    final decrypted = await decryptData(encryptedBase64, key);
    return jsonDecode(decrypted) as Map<String, dynamic>;
  }

  static Future<SecretKey> deriveKeyFromSeed(Uint8List seed) async {
    return SecretKey(seed);
  }
}
