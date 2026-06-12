import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/signaling_transport.dart';
import 'package:stealth/storage_service.dart';

/// Имя коллекции PocketBase, в которой хранятся сигнальные сообщения.
const String _kSignalingCollection = 'rtc_signaling';

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
    PocketBaseAuthService? authService,
  })  : _pb = pocketBase ?? PocketBaseClient.instance.pb,
        _connectivity = connectivity ?? Connectivity(),
        _authService = authService ??
            PocketBaseAuthService(
              pocketBase: pocketBase ?? PocketBaseClient.instance.pb,
              storage: storage ?? StorageService(),
            );

  final PocketBase _pb;
  final Connectivity _connectivity;
  final PocketBaseAuthService _authService;

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
    Logger.info('[signaling] connect',
        extras: {'roomId': roomId, 'selfUserId': selfUserId});
    _activeRoomId = roomId;
    _activeSelfUserId = selfUserId;

    await _authService.ensureAuth(selfUserId);
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
      const <String, dynamic>{'reason': 'hangup'},
    );
  }

  @override
  Future<void> disconnect() async {
    Logger.info('[signaling] disconnect', extras: {'roomId': _activeRoomId});
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
        Logger.warn('[signaling] unsubscribe error', extras: {'error': error});
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
      'payload': <String, dynamic>{
        ...payload,
        'creatorLocalId': selfUserId,
        'targetLocalId': targetUserId,
      },
    };
    final payloadSize = payload.toString().length;
    Logger.info('[signaling] send', extras: {
      'type': type.wireValue,
      'roomId': roomId,
      'pbTarget': pbTarget,
      'targetUserId': targetUserId,
      'payloadSize': payloadSize,
    });
    try {
      await _pb.collection(_kSignalingCollection).create(body: body);
    } catch (error) {
      Logger.warn('[signaling] send error',
          extras: {'type': type.wireValue, 'error': error});
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
    Logger.info('[signaling] subscribed', extras: {
      'roomId': roomId,
      'pbSelfId': pbSelfId,
    });
    try {
      _unsubscribe = await _pb
          .collection(_kSignalingCollection)
          .subscribe('*', _onRecord, filter: filter);
      _reconnectAttempt = 0;
      _emitState(SignalingConnectionState.connected);
    } catch (error) {
      Logger.warn('[signaling] subscribe error', extras: {'error': error});
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
      Logger.info('[signaling] recv', extras: {
        'type': message.type.wireValue,
        'roomId': message.roomId,
        'creator': message.creator,
      });
      if (!_incomingController.isClosed) {
        _incomingController.add(message);
      }
    } catch (error) {
      Logger.warn('[signaling] failed to parse record',
          extras: {'error': error});
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    Logger.debug('[signaling] connectivity changed', extras: {
      'results': results,
      'hasNetwork': hasNetwork,
    });
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
    Logger.info('[signaling] reconnect scheduled', extras: {
      'attempt': _reconnectAttempt,
      'delaySeconds': delaySeconds,
    });
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
}
