import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../crypto/aes_bytes.dart';
import '../../storage_service.dart';

/// Group-secret storage + on-demand encryption used by `MessageService`,
/// `AttachmentService` and `ChatManagementService` callbacks.
///
/// Encapsulates the in-memory cache + secure-storage persistence that
/// previously lived inside `LocalAppService`. Extracted as FIX_PLAN
/// Phase D so the facade can hit the honest <300-line target without
/// duplicating crypto state across services.
///
/// Lifecycle:
/// * `resolve(chatId)` — returns the existing key from cache,
///   loads from `flutter_secure_storage_x`, or mints a fresh AES-256-GCM
///   key and persists it. Mirrors the historical contract.
/// * `encryptForGroup` / `decryptForGroup` — convenience wrappers that
///   resolve the key once and delegate to the shared
///   [encryptBytesWithSecret] / [decryptBytesWithSecret] in
///   `crypto/aes_bytes.dart`.
/// * `clearOnLogout()` — drops the in-memory cache. Called from
///   `LocalAppService.logout()`. Persistent storage entries are wiped
///   by [StorageService] as part of its own logout flow.
class GroupSecretService {
  factory GroupSecretService() => _instance;
  GroupSecretService._();
  static final GroupSecretService _instance = GroupSecretService._();

  final StorageService _storage = StorageService();
  final AesGcm _aes = AesGcm.with256bits();
  final Map<String, SecretKey> _cache = {};

  Future<SecretKey> resolve(String chatId) async {
    if (_cache.containsKey(chatId)) {
      return _cache[chatId]!;
    }
    final keyName = 'group_key_$chatId';
    final stored = await _storage.read(keyName);
    if (stored != null && stored.isNotEmpty) {
      final key = SecretKey(base64Decode(stored));
      _cache[chatId] = key;
      return key;
    }
    final key = await _aes.newSecretKey();
    await _storage.write(keyName, base64Encode(await key.extractBytes()));
    _cache[chatId] = key;
    return key;
  }

  Future<String> encryptForGroup(String chatId, String content) async {
    final key = await resolve(chatId);
    return encryptBytesWithSecret(
        Uint8List.fromList(utf8.encode(content)), key);
  }

  Future<String> decryptForGroup(String chatId, String payload) async {
    final key = await resolve(chatId);
    final bytes = await decryptBytesWithSecret(payload, key);
    return utf8.decode(bytes);
  }

  void clearOnLogout() => _cache.clear();
}
