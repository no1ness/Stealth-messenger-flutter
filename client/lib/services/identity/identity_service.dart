import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../../logging/logger.dart';
import '../../storage_service.dart';

/// Local identity facade: own `user_id`, nickname, X25519 keypair, contact
/// bundle generation. Stateless singleton — backing state lives in
/// [StorageService].
///
/// Extracted from `LocalAppService` as task #5 of the post-PocketBase
/// hardening plan (`.ai-factory/plans/client-hardening-followup.md`).
/// Keeps the no-arg constructor convention used elsewhere in the client
/// (`factory StorageService() => _instance;`) so call sites need zero
/// changes when migrating off the old facade.
class IdentityService {
  factory IdentityService() => _instance;
  IdentityService._();
  static final IdentityService _instance = IdentityService._();

  final StorageService _storage = StorageService();
  final X25519 _algorithm = X25519();
  final Uuid _uuid = const Uuid();

  Future<String?> getUserId() => _storage.read('userId');

  Future<String?> getNickname() => _storage.read('nickname');

  Future<void> updateNickname(String nickname) async {
    Logger.debug('[identity] updateNickname');
    await _storage.write('nickname', nickname);
  }

  /// Generates an X25519 keypair, allocates a fresh user_id and persists
  /// the identity bundle. Caller must guard against repeated registration
  /// — this method does NOT no-op for already-registered users; it will
  /// overwrite keys (which is the intended behaviour for explicit re-init).
  Future<void> registerUser(String nickname) async {
    Logger.debug('[identity] registerUser begin');
    final userId = _uuid.v4();
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    await _storage.write('userId', userId);
    await _storage.write('nickname', nickname);
    await _storage.write('privateKey', base64Encode(privateKey));
    await _storage.write('publicKey', base64Encode(publicKey.bytes));
    await _storage.write('registeredAt', DateTime.now().toIso8601String());
    Logger.info(
      '[identity] registered local identity',
      extras: {'userId': userId},
    );
  }

  /// Clears every key in [StorageService]. Callers (LocalAppService) must
  /// also drop their own caches (shared-secret / group-secret / nickname)
  /// after this returns.
  Future<void> logout() async {
    Logger.info('[identity] logout — local storage cleared');
    await _storage.deleteAll();
  }

  /// Returns the persisted own X25519 keypair. Throws [StateError] if no
  /// keys are stored (user must call [registerUser] first).
  Future<SimpleKeyPair> getOwnKeyPair() async {
    final privateKeyBase64 = await _storage.read('privateKey');
    final publicKeyBase64 = await _storage.read('publicKey');
    if (privateKeyBase64 == null || publicKeyBase64 == null) {
      throw StateError(
          'Keys not found. User might not be registered (call registerUser first).');
    }
    return SimpleKeyPairData(
      base64Decode(privateKeyBase64),
      publicKey: SimplePublicKey(
        base64Decode(publicKeyBase64),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }

  /// Encodes own contact bundle for sharing with peers (QR / paste).
  /// Returns `''` when identity is incomplete (e.g. before registration).
  Future<String> generateQRCode() async {
    final userId = await getUserId();
    final nickname = await getNickname();
    final publicKey = await _storage.read('publicKey');
    if (userId == null || publicKey == null) {
      Logger.warn('[identity] generateQRCode skipped — no identity stored');
      return '';
    }
    return encodeOwnContactBundle(
      userId: userId,
      nickname: nickname ?? userId,
      publicKey: publicKey,
    );
  }

  /// Pure helper exposed for tests + reuse. Builds a `stealth:` bundle
  /// string with the canonical `v: 1` payload (user_id, name, public_key).
  String encodeOwnContactBundle({
    required String userId,
    required String nickname,
    required String publicKey,
  }) {
    final json = jsonEncode({
      'v': 1,
      'user_id': userId,
      'name': nickname,
      'public_key': publicKey,
    });
    return 'stealth:${base64UrlEncode(utf8.encode(json))}';
  }
}
