import 'rtc_message.dart';

/// Состояние соединения сигналингового транспорта.
///
/// Используется для отображения индикаторов «нет связи»/«переподключаемся»
/// и для логики retry при разрыве. Конкретные имплементации (PocketBase,
/// будущие альтернативы) должны эмитить эти значения через
/// [SignalingTransport.connectionState].
enum SignalingConnectionState {
  connected,
  reconnecting,
  disconnected,
  error,
}

/// Транспорт обмена сигнальными сообщениями WebRTC.
///
/// Абстракция позволяет менять бэкенд (PocketBase, кастомный WS-relay,
/// LAN-mDNS) без изменений в WebRTC-слое (`webrtc_call_screen_*.dart`,
/// `call_manager.dart`). На текущем этапе единственная имплементация —
/// `WebRtcSignalingService` поверх PocketBase Realtime SSE.
///
/// Жизненный цикл:
/// 1. `connect(roomId, selfUserId)` — поднимает подписку на сообщения,
///    адресованные `selfUserId` в указанной «комнате» (для 1:1 звонков
///    `roomId` совпадает с `chatId`).
/// 2. `incoming` начинает эмитить [RtcMessage] для всех принятых событий.
/// 3. `sendOffer/sendAnswer/sendCandidate/sendHangup` отправляют исходящие
///    сообщения адресно по `targetUserId`.
/// 4. `disconnect()` корректно закрывает подписку и потоки.
abstract class SignalingTransport {
  /// Подключается к сигналинг-каналу и начинает слушать входящие сообщения,
  /// адресованные [selfUserId] в указанной [roomId].
  Future<void> connect({
    required String roomId,
    required String selfUserId,
  });

  /// Отправляет SDP-offer в адрес [targetUserId].
  Future<void> sendOffer({
    required String roomId,
    required String targetUserId,
    required Map<String, dynamic> sdp,
  });

  /// Отправляет SDP-answer в адрес [targetUserId].
  Future<void> sendAnswer({
    required String roomId,
    required String targetUserId,
    required Map<String, dynamic> sdp,
  });

  /// Отправляет ICE-кандидат в адрес [targetUserId].
  Future<void> sendCandidate({
    required String roomId,
    required String targetUserId,
    required Map<String, dynamic> candidate,
  });

  /// Отправляет hangup-сигнал в адрес [targetUserId]. Получатель должен
  /// корректно закрыть свой `WebRTCCallScreen`. Это явная альтернатива
  /// ожиданию `iceConnectionState=disconnected` (15+ секунд).
  Future<void> sendHangup({
    required String roomId,
    required String targetUserId,
  });

  /// Поток входящих сообщений, отфильтрованных на стороне сервера так,
  /// чтобы `target == selfUserId`.
  Stream<RtcMessage> get incoming;

  /// Поток состояний транспорта. Для UI и логики retry.
  Stream<SignalingConnectionState> get connectionState;

  /// Отписывается от канала и закрывает все потоки. После вызова инстанс
  /// больше не используется — для нового звонка нужно создать новый.
  Future<void> disconnect();
}
