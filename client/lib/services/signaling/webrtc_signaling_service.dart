import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/signaling_transport.dart';
import 'package:stealth/storage_service.dart';

/// Имя коллекции PocketBase, в которой хранятся сигнальные сообщения.
const String _kSignalingCollection = 'rtc_signaling';

/// Ключи `StorageService` для персистентной аутентификации PocketBase.
const String _kPbTokenKey = 'pb_token';
const String _kPbUserIdKey = 'pb_user_id';
const String _kPbPasswordKey = 'pb_password';

/// PocketBase-имплементация [SignalingTransport].
///
/// Архитектура — см. `.ai-factory/plans/pocketbase-signaling.md`.
/// Кратко:
///
/// - Подписка `pb.collection('rtc_signaling').subscribe('*', cb,
///   filter: "roomId='\$roomId' && target='\$pbSelfId'")` ловит ВСЕ
///   адресованные пиру сообщения (offer/answer/candidate/hangup).
///   `pbSelfId` — PocketBase record id (локальный UUID без дефисов),
///   совпадает с `request.auth.id` под строгими API rules.
/// - Send-методы делают `create()` с body, сформированным в [RtcMessage].
///   `creator`/`target` записываются как PB-id (см. `pb_user_id.dart`),
///   что удовлетворяет правилу `@request.data.creator = @request.auth.id`.
/// - Аутентификация ленивая: на первый `connect()` пытается восстановить
///   токен из `flutter_secure_storage_x`; если идентичность изменилась
///   (старый PB-id != ожидаемого из текущего UUID) — выполняется
///   single-shot миграция: локальные creds стираются и регистрируется
///   новая запись с явным `id = pbSelfId`. Технический email содержит
///   тот же PB-id (`<pbSelfId>@stealth.local`) — это позволяет создать
///   новую запись поверх отсутствующего/orphan legacy аккаунта без
///   email-конфликта.
/// - Reconnect: при ошибке подписки или смене сети переподключается с
///   экспоненциальным backoff (1→2→4→8→16→30 секунд), эмитит состояние
///   через [connectionState].
class WebRtcSignalingService implements SignalingTransport {
  WebRtcSignalingService({
    PocketBase? pocketBase,
    StorageService? storage,
    Connectivity? connectivity,
  })  : _pb = pocketBase ?? PocketBaseClient.instance.pb,
        _storage = storage ?? StorageService(),
        _connectivity = connectivity ?? Connectivity();

  final PocketBase _pb;
  final StorageService _storage;
  final Connectivity _connectivity;

  final StreamController<RtcMessage> _incomingController =
      StreamController<RtcMessage>.broadcast();
  final StreamController<SignalingConnectionState> _stateController =
      StreamController<SignalingConnectionState>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  UnsubscribeFunc? _unsubscribe;

  String? _activeRoomId;
  String? _activeSelfUserId;
  bool _disposed = false;

  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  static const int _maxBackoffSeconds = 30;

  @override
  Stream<RtcMessage> get incoming => _incomingController.stream;

  @override
  Stream<SignalingConnectionState> get connectionState =>
      _stateController.stream;

  @override
  Future<void> connect({
    required String roomId,
    required String selfUserId,
  }) async {
    debugPrint(
      '[signaling] connect roomId=$roomId selfUserId=$selfUserId',
    );
    _activeRoomId = roomId;
    _activeSelfUserId = selfUserId;

    await _ensureAuth(selfUserId);
    await _subscribe();

    _connectivitySub ??= _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
  }

  @override
  Future<void> sendOffer({
    required String roomId,
    required String targetUserId,
    required Map<String, dynamic> sdp,
  }) {
    return _send(RtcMessageType.offer, roomId, targetUserId, sdp);
  }

  @override
  Future<void> sendAnswer({
    required String roomId,
    required String targetUserId,
    required Map<String, dynamic> sdp,
  }) {
    return _send(RtcMessageType.answer, roomId, targetUserId, sdp);
  }

  @override
  Future<void> sendCandidate({
    required String roomId,
    required String targetUserId,
    required Map<String, dynamic> candidate,
  }) {
    return _send(RtcMessageType.candidate, roomId, targetUserId, candidate);
  }

  @override
  Future<void> sendHangup({
    required String roomId,
    required String targetUserId,
  }) {
    return _send(
      RtcMessageType.hangup,
      roomId,
      targetUserId,
      const <String, dynamic>{},
    );
  }

  @override
  Future<void> disconnect() async {
    debugPrint('[signaling] disconnect roomId=$_activeRoomId');
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    if (unsubscribe != null) {
      try {
        await unsubscribe();
      } catch (error) {
        debugPrint('[signaling] unsubscribe error: $error');
      }
    }
    if (!_stateController.isClosed) {
      _stateController.add(SignalingConnectionState.disconnected);
      await _stateController.close();
    }
    if (!_incomingController.isClosed) {
      await _incomingController.close();
    }
  }

  Future<void> _send(
    RtcMessageType type,
    String roomId,
    String targetUserId,
    Map<String, dynamic> payload,
  ) async {
    final selfUserId = _activeSelfUserId;
    if (selfUserId == null) {
      throw StateError(
        'WebRtcSignalingService.connect must be called before sending messages',
      );
    }
    final pbCreator = pbIdFromLocalUuid(selfUserId);
    final pbTarget = pbIdFromLocalUuid(targetUserId);
    final body = <String, dynamic>{
      'roomId': roomId,
      'creator': pbCreator,
      'target': pbTarget,
      'type': type.wireValue,
      'payload': payload,
    };
    final payloadSize = payload.toString().length;
    debugPrint(
      '[signaling] send type=${type.wireValue} room=$roomId '
      'to=$pbTarget (localUuid=$targetUserId) payloadSize=$payloadSize',
    );
    try {
      await _pb.collection(_kSignalingCollection).create(body: body);
    } catch (error) {
      debugPrint('[signaling] send error type=${type.wireValue}: $error');
      rethrow;
    }
  }

  Future<void> _subscribe() async {
    final roomId = _activeRoomId;
    final selfUserId = _activeSelfUserId;
    if (roomId == null || selfUserId == null) return;

    // Старая подписка может ещё висеть после reconnect; корректно её снимаем.
    final previous = _unsubscribe;
    _unsubscribe = null;
    if (previous != null) {
      try {
        await previous();
      } catch (_) {/* ignore stale unsubscribe failure */}
    }

    final pbSelfId = pbIdFromLocalUuid(selfUserId);
    final filter = "roomId='$roomId' && target='$pbSelfId'";
    debugPrint("[signaling] subscribed filter='$filter'");
    try {
      _unsubscribe = await _pb
          .collection(_kSignalingCollection)
          .subscribe('*', _onRecord, filter: filter);
      _reconnectAttempt = 0;
      _emitState(SignalingConnectionState.connected);
    } catch (error) {
      debugPrint('[signaling] subscribe error: $error');
      _emitState(SignalingConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onRecord(RecordSubscriptionEvent event) {
    if (_disposed) return;
    final record = event.record;
    if (record == null) return;
    if (event.action != 'create') {
      // Сигналинг — append-only; update/delete нас не интересуют.
      return;
    }
    try {
      final message = RtcMessage.fromRecord(record);
      debugPrint(
        '[signaling] recv type=${message.type.wireValue} '
        'room=${message.roomId} from=${message.creator}',
      );
      if (!_incomingController.isClosed) {
        _incomingController.add(message);
      }
    } catch (error) {
      debugPrint('[signaling] failed to parse record: $error');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    debugPrint('[signaling] connectivity changed: $results hasNetwork=$hasNetwork');
    if (hasNetwork) {
      _scheduleReconnect(immediate: true);
    } else {
      _emitState(SignalingConnectionState.disconnected);
    }
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final delaySeconds = immediate
        ? 0
        : math.min(_maxBackoffSeconds, math.pow(2, _reconnectAttempt).toInt());
    _reconnectAttempt += 1;
    debugPrint(
      '[signaling] reconnect scheduled attempt=$_reconnectAttempt '
      'delay=${delaySeconds}s',
    );
    _emitState(SignalingConnectionState.reconnecting);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_disposed) return;
      await _subscribe();
    });
  }

  void _emitState(SignalingConnectionState state) {
    if (_stateController.isClosed) return;
    _stateController.add(state);
  }

  /// Восстанавливает либо создаёт PocketBase-аккаунт для текущего юзера.
  ///
  /// Контракт идентичности: запись в коллекции `users` имеет
  /// `id == pbIdFromLocalUuid(selfUserId)`. Это требуется строгими API
  /// rules (`@request.data.creator = @request.auth.id`) и достигается
  /// явной передачей `id` в `create()` body. Email строится из того же
  /// PB-id (`<pbId>@stealth.local`), чтобы устаревшие email от прежних
  /// сборок (с дефисами в адресе) не блокировали повторную регистрацию.
  ///
  /// Migration path: если в secure_storage сохранён `pb_user_id`, который
  /// не совпадает с ожидаемым PB-id (legacy auto-generated id), локальные
  /// PB-credentials стираются. Прежняя запись на сервере остаётся
  /// orphan — она недоступна под новой identity, а истечёт через
  /// signaling TTL hook (см. `docs/POCKETBASE_SETUP.md`).
  Future<void> _ensureAuth(String selfUserId) async {
    final expectedPbId = pbIdFromLocalUuid(selfUserId);

    await _migrateLegacyAuthIfNeeded(expectedPbId);

    if (_pb.authStore.isValid) {
      final model = _pb.authStore.model;
      final modelId = (model is RecordModel) ? model.id : null;
      if (modelId == expectedPbId) {
        debugPrint('[signaling] auth already valid pbId=$expectedPbId');
        return;
      }
      debugPrint(
        '[signaling] authStore identity mismatch '
        '(model.id=$modelId, expected=$expectedPbId) — clearing',
      );
      _pb.authStore.clear();
    }

    final storedToken = await _storage.read(_kPbTokenKey);
    final storedPbUserId = await _storage.read(_kPbUserIdKey);
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
      debugPrint('[signaling] auth restored from storage pbId=$storedPbUserId');
      return;
    }

    final email = '$expectedPbId@stealth.local';
    String? password = await _storage.read(_kPbPasswordKey);
    if (password == null || password.isEmpty) {
      password = _generatePassword();
      await _storage.write(_kPbPasswordKey, password);
    }

    RecordAuth auth;
    try {
      auth = await _pb.collection('users').authWithPassword(email, password);
      debugPrint(
        '[signaling] auth restored via password pbId=${auth.record?.id}',
      );
    } catch (loginError) {
      debugPrint(
        '[signaling] login failed, creating new account: $loginError',
      );
      await _pb.collection('users').create(body: <String, dynamic>{
        'id': expectedPbId,
        'email': email,
        'password': password,
        'passwordConfirm': password,
        'name': selfUserId,
      });
      auth = await _pb.collection('users').authWithPassword(email, password);
      debugPrint(
        '[signaling] auth created new user pbId=${auth.record?.id} '
        '(expected=$expectedPbId)',
      );
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
    await _storage.write(_kPbTokenKey, auth.token);
    await _storage.write(_kPbUserIdKey, actualPbId);
  }

  /// Wipes locally cached PocketBase auth if the stored id no longer matches
  /// the deterministic id derived from the current local UUID. This handles
  /// upgrades from builds that used an auto-generated PB record id.
  Future<void> _migrateLegacyAuthIfNeeded(String expectedPbId) async {
    final storedPbUserId = await _storage.read(_kPbUserIdKey);
    if (storedPbUserId == null || storedPbUserId.isEmpty) return;
    if (storedPbUserId == expectedPbId) return;
    debugPrint(
      '[signaling] legacy auth detected, migrating pbId=$storedPbUserId → '
      '$expectedPbId',
    );
    await _storage.delete(_kPbTokenKey);
    await _storage.delete(_kPbUserIdKey);
    await _storage.delete(_kPbPasswordKey);
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
