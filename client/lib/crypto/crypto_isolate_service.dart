import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;

class _DecryptBatchRequest {
  final List<String> encryptedPayloads;
  final Uint8List keyBytes;
  const _DecryptBatchRequest({
    required this.encryptedPayloads,
    required this.keyBytes,
  });
}

Future<List<String>> _decryptBatchInIsolate(
    _DecryptBatchRequest request) async {
  final aes = AesGcm.with256bits();
  final key = SecretKey(request.keyBytes);
  final results = <String>[];
  for (final encrypted in request.encryptedPayloads) {
    final concatenation = base64Decode(encrypted);
    final secretBox = SecretBox.fromConcatenation(
      concatenation,
      nonceLength: aes.nonceLength,
      macLength: aes.macAlgorithm.macLength,
    );
    final clearBytes = await aes.decrypt(
      secretBox,
      secretKey: key,
    );
    results.add(utf8.decode(clearBytes));
  }
  return results;
}

class CryptoIsolateService {
  static Future<List<String>> decryptBatch({
    required List<String> encryptedPayloads,
    required SecretKey key,
  }) async {
    if (encryptedPayloads.isEmpty) return const [];
    if (encryptedPayloads.length < 3) {
      final aes = AesGcm.with256bits();
      return Future.wait(encryptedPayloads.map((encrypted) async {
        final concatenation = base64Decode(encrypted);
        final secretBox = SecretBox.fromConcatenation(
          concatenation,
          nonceLength: aes.nonceLength,
          macLength: aes.macAlgorithm.macLength,
        );
        final clearBytes = await aes.decrypt(
          secretBox,
          secretKey: key,
        );
        return utf8.decode(clearBytes);
      }));
    }
    final keyBytes = Uint8List.fromList(await key.extractBytes());
    return compute(
      _decryptBatchInIsolate,
      _DecryptBatchRequest(
        encryptedPayloads: encryptedPayloads,
        keyBytes: keyBytes,
      ),
    );
  }
}
