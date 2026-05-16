import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/services/signaling/rtc_message.dart';

/// Базовое событие, эмитимое [IncomingCallSignalingService].
sealed class IncomingCallEvent {
  String get roomId;
  String get fromUserId;
}

/// Входящий звонок. Содержит уже принятый offer SDP — экран
/// `WebRTCCallScreen` при открытии должен сразу применить его через
/// `setRemoteDescription`, не дожидаясь повторной подписки.
///
/// Это устраняет race condition прежней архитектуры: callee
/// нажимал Answer, экран открывался, экран подписывался на `chat_calls`,
/// и только после этого caller получал `call_accept` и слал offer в
/// канал — который callee уже мог пропустить.
class IncomingCallOffer extends IncomingCallEvent {
  IncomingCallOffer({
    required this.roomId,
    required this.fromUserId,
    required this.fromNickname,
    required this.isVideoCall,
    required this.sdp,
  });

  @override
  final String roomId;
  @override
  final String fromUserId;

  /// Никнейм звонящего, если был положен в payload.
  final String fromNickname;
  final bool isVideoCall;

  /// Сырой SDP offer как `Map { 'sdp': ..., 'type': 'offer' }` —
  /// готов к передаче в `RTCSessionDescription`.
  final Map<String, dynamic> sdp;
}

/// Hangup от пира. Если на момент получения у нас открыт диалог
/// входящего звонка — `CallManager` должен его закрыть. Если открыт
/// сам экран звонка — он сам обработает hangup через свой
/// `WebRtcSignalingService.incoming`.
class IncomingCallHangup extends IncomingCallEvent {
  IncomingCallHangup({
    required this.roomId,
    required this.fromUserId,
  });

  @override
  final String roomId;
  @override
  final String fromUserId;
}

/// Глобальный слушатель входящих сигнальных событий, адресованных
/// текущему юзеру, для всех комнат сразу.
///
/// Запускается при старте приложения (из `CallManager`) и работает
/// на протяжении всей сессии. В отличие от `WebRtcSignalingService`,
/// который привязан к конкретной комнате на время одного звонка, этот
/// сервис ловит ВСЕ события `target=selfUserId` независимо от roomId
/// — поэтому именно он отвечает за приём `offer` (= новый звонок) и
/// `hangup` от ещё не отвеченных звонков.
class IncomingCallSignalingService {
  IncomingCallSignalingService({
    PocketBase? pocketBase,
    Iterable<String> Function()? knownPeerUuidsProvider,
    PocketBaseAuthService? authService,
  })  : _pb = pocketBase ?? PocketBaseClient.instance.pb,
        _knownPeerUuidsProvider =
            knownPeerUuidsProvider ?? (() => const <String>[]),
        _authService = authService ??
            (pocketBase == null
                ? PocketBaseAuthService.instance
                : PocketBaseAuthService(pocketBase: pocketBase));

  final PocketBase _pb;
  final PocketBaseAuthService _authService;
  final StreamController<IncomingCallEvent> _eventsController =
      StreamController<IncomingCallEvent>.broadcast();

  /// Returns local UUIDs the host can decode from incoming PB-id wire form
  /// (typically self + every contact). Called per-record because contacts
  /// can change at runtime; the lookup is cheap.
  final Iterable<String> Function() _knownPeerUuidsProvider;

  UnsubscribeFunc? _unsubscribe;
  String? _selfUserId;

  Stream<IncomingCallEvent> get events => _eventsController.stream;

  Future<void> start({required String selfUserId}) async {
    _selfUserId = selfUserId;
    // PocketBase realtime evaluates `listRule` per SSE event. Without auth,
    // `target = @request.auth.id` is always false and the callee never
    // receives an incoming offer. Ensure auth BEFORE subscribing so the
    // server attaches the right identity to this SSE client.
    await _authService.ensureAuth(selfUserId);
    final pbSelfId = pbIdFromLocalUuid(selfUserId);
    final filter = "target='$pbSelfId' && "
        "(type='offer' || type='hangup')";
    Logger.info('[signaling] incoming-call subscribe',
        extras: {'pbSelfId': pbSelfId});
    try {
      _unsubscribe = await _pb
          .collection('rtc_signaling')
          .subscribe('*', _onRecord, filter: filter);
    } catch (error) {
      Logger.warn('[signaling] incoming-call subscribe error',
          extras: {'error': error});
      rethrow;
    }
  }

  Future<void> stop() async {
    Logger.info('[signaling] incoming-call stop');
    final unsub = _unsubscribe;
    _unsubscribe = null;
    if (unsub != null) {
      try {
        await unsub();
      } catch (error) {
        Logger.warn('[signaling] incoming-call unsubscribe error',
            extras: {'error': error});
      }
    }
    if (!_eventsController.isClosed) {
      await _eventsController.close();
    }
  }

  /// Отправляет hangup в адрес caller'а (используется CallManager при
  /// нажатии Decline до открытия экрана звонка). Это убирает у caller'а
  /// «зависший» экран с гудками — за ~1 сек придёт hangup и экран
  /// закроется.
  Future<void> declineCall({
    required String roomId,
    required String callerUserId,
    required String selfUserId,
  }) async {
    final pbCreator = pbIdFromLocalUuid(selfUserId);
    final pbTarget = pbIdFromLocalUuid(callerUserId);
    Logger.info('[signaling] decline call', extras: {
      'roomId': roomId,
      'pbTarget': pbTarget,
      'callerUserId': callerUserId,
    });
    try {
      await _pb.collection('rtc_signaling').create(body: {
        'roomId': roomId,
        'creator': pbCreator,
        'target': pbTarget,
        'type': RtcMessageType.hangup.wireValue,
        'payload': <String, dynamic>{'creatorUuid': selfUserId},
      });
    } catch (error) {
      Logger.warn('[signaling] decline error', extras: {'error': error});
    }
  }

  void _onRecord(RecordSubscriptionEvent event) {
    if (event.action != 'create') return;
    final record = event.record;
    if (record == null) return;
    if (_eventsController.isClosed) return;
    try {
      final knownUuids = <String>{
        if (_selfUserId != null) _selfUserId!,
        ..._knownPeerUuidsProvider(),
      };
      final resolver = PbUserIdResolver(knownUuids);
      final message = RtcMessage.fromRecord(record, resolver: resolver);
      switch (message.type) {
        case RtcMessageType.offer:
          if (message.payload['purpose'] == 'datachannel') {
            Logger.debug(
              '[FIX:local-only] incoming datachannel offer ignored by call manager',
            );
            break;
          }
          final isVideoCall = (message.payload['callType'] ?? '') == 'video';
          final fromNickname = (message.payload['nickname'] ?? '') as String;
          // Prefer the caller UUID carried in the payload over `message.creator`
          // (which is a 15-char hash and may not resolve back to a UUID for
          // strangers not yet in the receiver's contacts).
          final creatorUuid = message.payload['creatorUuid'];
          final fromUserId = (creatorUuid is String && creatorUuid.isNotEmpty)
              ? creatorUuid
              : message.creator;
          Logger.info('[signaling] incoming offer detected', extras: {
            'roomId': message.roomId,
            'fromUserId': fromUserId,
          });
          _eventsController.add(IncomingCallOffer(
            roomId: message.roomId,
            fromUserId: fromUserId,
            fromNickname: fromNickname,
            isVideoCall: isVideoCall,
            sdp: message.payload,
          ));
          break;
        case RtcMessageType.hangup:
          final creatorUuid = message.payload['creatorUuid'];
          final fromUserId = (creatorUuid is String && creatorUuid.isNotEmpty)
              ? creatorUuid
              : message.creator;
          Logger.info('[signaling] incoming hangup', extras: {
            'roomId': message.roomId,
            'fromUserId': fromUserId,
          });
          _eventsController.add(IncomingCallHangup(
            roomId: message.roomId,
            fromUserId: fromUserId,
          ));
          break;
        case RtcMessageType.answer:
        case RtcMessageType.candidate:
          // Эти события обрабатывает per-call WebRtcSignalingService
          // внутри открытого WebRTCCallScreen — нам они здесь не нужны.
          break;
      }
    } catch (error) {
      Logger.warn('[signaling] incoming-call parse error',
          extras: {'error': error});
    }
  }

  @visibleForTesting
  String? get selfUserIdForTests => _selfUserId;
}
