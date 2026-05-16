import 'dart:async';
import 'dart:math' as math;

import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/storage_service.dart';

/// Ключи [StorageService] для персистентной PocketBase-аутентификации.
const String kPbTokenKey = 'pb_token';
const String kPbUserIdKey = 'pb_user_id';
const String kPbPasswordKey = 'pb_password';

/// Регистрирует/восстанавливает PocketBase-аккаунт текущего юзера.
///
/// Контракт идентичности: запись в коллекции `users` имеет
/// `id == pbIdFromLocalUuid(selfUserId)` (см. `pb_user_id.dart`). Это
/// требуется строгими API rules коллекции `rtc_signaling`
/// (`@request.data.creator = @request.auth.id`).
///
/// Делится между [WebRtcSignalingService] (per-call отправитель/подписчик)
/// и [IncomingCallSignalingService] (глобальная подписка callee). Обе
/// стороны должны иметь валидный auth.token, иначе PocketBase listRule
/// `target = @request.auth.id || creator = @request.auth.id` фильтрует
/// все SSE-события — и callee никогда не увидит incoming offer.
///
/// In-flight guard: повторный вызов [ensureAuth] во время текущего —
/// no-op, ждёт уже запущенный future. Это защищает от race между двумя
/// сервисами при первом старте сессии (один и тот же PocketBase singleton
/// иначе создаст два конкурентных `users.create` под одной почтой).
///
/// Migration: если в secure_storage сохранён `pb_user_id`, не совпадающий
/// с ожидаемым PB-id (legacy auto-generated id из прежних сборок), —
/// локальные креды стираются и регистрация идёт заново. Прежняя запись
/// на сервере остаётся orphan и истекает через TTL hook (см.
/// `docs/POCKETBASE_SETUP.md`).
class PocketBaseAuthService {
  PocketBaseAuthService({PocketBase? pocketBase, StorageService? storage})
      : _pb = pocketBase ?? PocketBaseClient.instance.pb,
        _storage = storage ?? StorageService();

  /// Process-wide singleton, чтобы in-flight guard работал между
  /// [WebRtcSignalingService] и [IncomingCallSignalingService], которые
  /// делят один и тот же [PocketBase] клиент.
  static final PocketBaseAuthService instance = PocketBaseAuthService();

  final PocketBase _pb;
  final StorageService _storage;
  Future<void>? _inFlight;

  /// Восстанавливает либо создаёт PocketBase-аккаунт для [selfUserId].
  /// Идемпотентна: после первого успешного вызова повторы — no-op, если
  /// `_pb.authStore` уже валиден и совпадает по id.
  Future<void> ensureAuth(String selfUserId) {
    return _inFlight ??=
        _doEnsureAuth(selfUserId).whenComplete(() => _inFlight = null);
  }

  Future<void> _doEnsureAuth(String selfUserId) async {
    final expectedPbId = pbIdFromLocalUuid(selfUserId);

    await _migrateLegacyAuthIfNeeded(expectedPbId);

    if (_pb.authStore.isValid) {
      final model = _pb.authStore.model;
      final modelId = (model is RecordModel) ? model.id : null;
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

    final storedToken = await _storage.read(kPbTokenKey);
    final storedPbUserId = await _storage.read(kPbUserIdKey);
    if (storedToken != null &&
        storedToken.isNotEmpty &&
        storedPbUserId == expectedPbId) {
      _pb.authStore.save(
        storedToken,
        RecordModel(
          id: storedPbUserId!,
          collectionId: 'users',
          collectionName: 'users',
        ),
      );
      Logger.info('[signaling] auth restored from storage',
          extras: {'pbId': storedPbUserId});
      return;
    }

    final email = '$expectedPbId@stealth.local';
    String? password = await _storage.read(kPbPasswordKey);
    if (password == null || password.isEmpty) {
      password = _generatePassword();
      await _storage.write(kPbPasswordKey, password);
    }

    RecordAuth auth;
    try {
      auth = await _pb.collection('users').authWithPassword(email, password);
      Logger.info('[signaling] auth restored via password',
          extras: {'pbId': auth.record?.id});
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
        'pbId': auth.record?.id,
        'expectedPbId': expectedPbId,
      });
    }

    final actualPbId = auth.record?.id;
    if (actualPbId == null || actualPbId != expectedPbId) {
      throw StateError(
        '[signaling] auth id mismatch: expected=$expectedPbId, '
        'got=${actualPbId ?? "null"}. The PocketBase users collection '
        'rejected the custom id or a legacy account is shadowing the '
        'email. Reset local credentials to recover.',
      );
    }
    await _storage.write(kPbTokenKey, auth.token);
    await _storage.write(kPbUserIdKey, actualPbId);
  }

  Future<void> _migrateLegacyAuthIfNeeded(String expectedPbId) async {
    final storedPbUserId = await _storage.read(kPbUserIdKey);
    if (storedPbUserId == null || storedPbUserId.isEmpty) return;
    if (storedPbUserId == expectedPbId) return;
    Logger.info('[signaling] legacy auth detected, migrating', extras: {
      'storedPbUserId': storedPbUserId,
      'expectedPbId': expectedPbId,
    });
    await _storage.delete(kPbTokenKey);
    await _storage.delete(kPbUserIdKey);
    await _storage.delete(kPbPasswordKey);
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
