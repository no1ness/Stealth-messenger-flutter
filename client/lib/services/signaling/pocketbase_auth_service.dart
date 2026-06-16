import 'dart:async';
import 'dart:math' as math;

import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/storage_service.dart';

/// Shared lazy PocketBase auth for every signaling subscriber/sender.
///
/// WebRTC has two signaling entry points:
/// - per-room [WebRtcSignalingService];
/// - global incoming-call listener.
///
/// Both must authenticate the same deterministic PocketBase user before
/// subscribing or creating records, otherwise strict `rtc_signaling` rules
/// reject writes and private realtime subscriptions may miss incoming calls.
class PocketBaseAuthService {
  PocketBaseAuthService({
    required PocketBase pocketBase,
    required StorageService storage,
  })  : _pb = pocketBase,
        _storage = storage;

  PocketBase _pb;
  final StorageService _storage;

  void reconfigure(PocketBase pocketBase) {
    _pb = pocketBase;
  }

  static final Map<int, Future<void>> _authInFlightByClient =
      <int, Future<void>>{};

  static const String _pbTokenKey = 'pb_token';
  static const String _pbUserIdKey = 'pb_user_id';
  static const String _pbPasswordKey = 'pb_password';

  Future<void> ensureAuth(String selfUserId) {
    final clientKey = identityHashCode(_pb);
    final inFlight = _authInFlightByClient[clientKey];
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _authInFlightByClient[clientKey] = completer.future;

    _doEnsureAuth(selfUserId).then(
      (_) {
        _authInFlightByClient.remove(clientKey);
        completer.complete();
      },
      onError: (Object e, StackTrace s) {
        _authInFlightByClient.remove(clientKey);
        completer.completeError(e, s);
      },
    );

    return completer.future;
  }

  Future<void> _doEnsureAuth(String selfUserId) async {
    final expectedPbId = pbIdFromLocalUuid(selfUserId);

    await _migrateLegacyAuthIfNeeded(expectedPbId);

    if (_pb.authStore.isValid) {
      final record = _pb.authStore.record;
      final modelId = record?.id;
      if (modelId == expectedPbId) {
        Logger.debug('[signaling] auth already valid',
            extras: {'pbId': expectedPbId});
        return;
      }
      Logger.warn(
        '[signaling] authStore identity mismatch — clearing',
        extras: {'modelId': modelId, 'expectedPbId': expectedPbId},
      );
      _pb.authStore.clear();
    }

    final storedToken = await _storage.read(_pbTokenKey);
    final storedPbUserId = await _storage.read(_pbUserIdKey);
    if (storedToken != null &&
        storedToken.isNotEmpty &&
        storedPbUserId == expectedPbId) {
      _pb.authStore.save(
        storedToken,
        RecordModel({
          'id': storedPbUserId!,
          'collectionId': 'users',
          'collectionName': 'users',
        }),
      );
      Logger.info('[signaling] auth restored from storage',
          extras: {'pbId': storedPbUserId});
      return;
    }

    final email = '$expectedPbId@stealth.local';
    String? password = await _storage.read(_pbPasswordKey);
    if (password == null || password.isEmpty) {
      password = _generatePassword();
      await _storage.write(_pbPasswordKey, password);
    }

    RecordAuth auth;
    try {
      auth = await _pb.collection('users').authWithPassword(email, password);
      Logger.info('[signaling] auth restored via password',
          extras: {'pbId': auth.record.id});
    } catch (loginError) {
      Logger.info('[signaling] login failed, creating new account',
          extras: {'error': loginError});
      await _pb.collection('users').create(body: <String, dynamic>{
        'id': expectedPbId,
        'email': email,
        'password': password,
        'passwordConfirm': password,
        'name': selfUserId,
      });
      auth = await _pb.collection('users').authWithPassword(email, password);
      Logger.info('[signaling] auth created new user', extras: {
        'pbId': auth.record.id,
        'expectedPbId': expectedPbId,
      });
    }

    final actualPbId = auth.record.id;
    if (actualPbId.isEmpty || actualPbId != expectedPbId) {
      throw StateError(
        '[signaling] auth id mismatch: expected=$expectedPbId, '
        'got=$actualPbId. The PocketBase users collection rejected '
        'the custom id or a legacy account is shadowing the email. '
        'Reset local credentials to recover.',
      );
    }
    await _storage.write(_pbTokenKey, auth.token);
    await _storage.write(_pbUserIdKey, actualPbId);
  }

  Future<void> _migrateLegacyAuthIfNeeded(String expectedPbId) async {
    final storedPbUserId = await _storage.read(_pbUserIdKey);
    if (storedPbUserId == null || storedPbUserId.isEmpty) return;
    if (storedPbUserId == expectedPbId) return;
    Logger.info('[signaling] legacy auth detected, migrating', extras: {
      'storedPbUserId': storedPbUserId,
      'expectedPbId': expectedPbId,
    });
    await _storage.delete(_pbTokenKey);
    await _storage.delete(_pbUserIdKey);
    await _storage.delete(_pbPasswordKey);
    _pb.authStore.clear();
  }

  String _generatePassword() {
    final rand = math.Random.secure();
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(
      24,
      (_) => alphabet[rand.nextInt(alphabet.length)],
    ).join();
  }
}
