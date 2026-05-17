import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/peer_resolver.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/signaling_transport.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/ui/screens/calls/native_call_media_bindings.dart';

typedef SignalingBuilder = SignalingTransport Function();

/// Контроллер native-варианта `WebRTCCallScreen`.
///
/// Держит signaling-подписку, peer-resolver, таймеры, флаги UI (mute/
/// speaker/camera/connected/initializing/closing) и длительность звонка.
/// Делегирует все WebRTC-операции в [NativeCallMediaBindings].
///
/// Lazy-init signaling сохранён: [WebRtcSignalingService] создаётся в
/// [initialize] только после прохождения permission gate — иначе в
/// widget-тестах без `dotenv` field-init State падал бы на
/// `PocketBaseClient.instance` (см. webrtc_call_screen_semantics_test).
class NativeCallController extends ChangeNotifier {
  NativeCallController({
    required this.chatId,
    required this.isCaller,
    required this.isVideoCall,
    this.initialOffer,
    this.callerUserId,
    NativeCallMediaBindings? media,
    LocalAppService? appService,
    PeerResolver? peerResolver,
    SignalingBuilder? signalingBuilder,
    this.onError,
    this.onClose,
  })  : media = media ?? NativeCallMediaBindings(),
        _appService = appService ?? LocalAppService(),
        _peerResolver = peerResolver ?? PeerResolver(),
        _signalingBuilder =
            signalingBuilder ?? (() => WebRtcSignalingService());

  final String chatId;
  final bool isCaller;
  final bool isVideoCall;
  final Map<String, dynamic>? initialOffer;
  final String? callerUserId;

  final NativeCallMediaBindings media;
  final LocalAppService _appService;
  final PeerResolver _peerResolver;
  final SignalingBuilder _signalingBuilder;

  /// Вызывается, когда контроллеру нужно показать пользователю сообщение об
  /// ошибке (permission denied, setup failed, connection timeout).
  final void Function(String message)? onError;

  /// Вызывается, когда контроллер хочет закрыть экран (remote hangup,
  /// permission denied при старте, setup error).
  final VoidCallback? onClose;

  SignalingTransport? _signaling;
  StreamSubscription<RtcMessage>? _signalingSub;
  Timer? _connectionTimeout;
  Timer? _callTimer;

  String? _selfUserId;
  String? _targetUserId;

  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = true;
  bool _initializing = true;
  bool _connected = false;
  bool _closing = false;
  bool _startRequested = false;
  int _callDurationSeconds = 0;

  bool get microphoneEnabled => _microphoneEnabled;
  bool get cameraEnabled => _cameraEnabled;
  bool get speakerEnabled => _speakerEnabled;
  bool get initializing => _initializing;
  bool get connected => _connected;
  bool get closing => _closing;
  int get callDurationSeconds => _callDurationSeconds;
  String? get selfUserId => _selfUserId;
  String? get targetUserId => _targetUserId;

  Future<void> initialize() async {
    if (_startRequested) return;
    _startRequested = true;
    try {
      await media.initializeRenderers();
      final permissionError = kIsWeb
          ? null
          : await media.requestPermissions(isVideoCall: isVideoCall);
      if (permissionError != null) {
        _initializing = false;
        notifyListeners();
        onError?.call(permissionError);
        onClose?.call();
        return;
      }

      debugPrint('[FIX] webrtc-call: lazy WebRtcSignalingService init');
      _signaling = _signalingBuilder();

      _selfUserId = await _appService.getUserId();
      if (_selfUserId == null) {
        throw StateError('Cannot start call: missing local user id');
      }
      if (isCaller) {
        _targetUserId = await _peerResolver.resolveTarget(
          chatId: chatId,
          selfUserId: _selfUserId!,
        );
      } else {
        _targetUserId = callerUserId;
        if (_targetUserId == null) {
          throw StateError('Callee opened without callerUserId');
        }
      }
      debugPrint(
        '[stealth-call] using signaling=PocketBase '
        'self=$_selfUserId target=$_targetUserId isCaller=$isCaller',
      );

      await media.createPeerConnection(
        onLocalCandidate: _handleLocalCandidate,
        onRemoteStreamReady: () async => notifyListeners(),
        onIceConnectionState: _handleIceConnectionState,
      );
      await media.createLocalStream(isVideoCall: isVideoCall);
      await media.attachLocalMedia(isVideoCall: isVideoCall);
      await media.applyAudioRouting();

      await _signaling!.connect(
        roomId: chatId,
        selfUserId: _selfUserId!,
      );
      _signalingSub = _signaling!.incoming.listen(_onSignalingMessage);

      _connectionTimeout = Timer(const Duration(seconds: 120), () {
        if (!_connected) {
          onError?.call('Connection timed out.');
          hangUp();
        }
      });

      if (isCaller) {
        debugPrint('[stealth-call] caller — creating offer immediately');
        await _sendOffer();
      } else {
        final offerMap = initialOffer;
        if (offerMap != null) {
          debugPrint('[stealth-call] callee — applying initialOffer');
          await _applyRemoteOffer(RTCSessionDescription(
            offerMap['sdp'] as String?,
            offerMap['type'] as String?,
          ));
        } else {
          debugPrint('[stealth-call] callee — waiting for offer via signaling');
        }
      }

      _initializing = false;
      notifyListeners();
    } catch (error) {
      debugPrint('WebRTC init error: $error');
      _initializing = false;
      notifyListeners();
      onError?.call('Call setup failed: $error');
      onClose?.call();
    }
  }

  void _handleLocalCandidate(RTCIceCandidate candidate) {
    final target = _targetUserId;
    if (target == null) return;
    // ignore: discarded_futures
    _signaling?.sendCandidate(
      roomId: chatId,
      targetUserId: target,
      candidate: candidate.toMap(),
    );
  }

  void _handleIceConnectionState(RTCIceConnectionState state) {
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _markConnected();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      debugPrint(
          '[stealth-call] ICE Connection Failed - triggering restart if possible');
      onError?.call('Connection failed. Retrying...');
      hangUp();
    } else if (state ==
        RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      debugPrint('[stealth-call] ICE Connection Disconnected');
    }
  }

  Future<void> _sendOffer() async {
    final payload = await media.createLocalOffer(isVideoCall: isVideoCall);
    final target = _targetUserId;
    if (payload == null || target == null) return;
    // Кладём nickname и callType прямо в payload offer-а — это позволяет
    // IncomingCallSignalingService на стороне callee сразу показать
    // диалог входящего звонка с правильным именем и типом.
    final nickname = await _appService.getNickname();
    final enriched = <String, dynamic>{
      ...payload,
      'purpose': 'call',
      'nickname': nickname ?? '',
      'callType': isVideoCall ? 'video' : 'audio',
      // `creatorUuid` is injected automatically by WebRtcSignalingService._send.
    };
    await _signaling!.sendOffer(
      roomId: chatId,
      targetUserId: target,
      sdp: enriched,
    );
  }

  Future<void> _applyRemoteOffer(RTCSessionDescription offer) async {
    final answer = await media.applyRemoteOffer(offer);
    final target = _targetUserId;
    if (answer == null || target == null) return;
    await _signaling!.sendAnswer(
      roomId: chatId,
      targetUserId: target,
      sdp: answer,
    );
    debugPrint('[stealth-call] answer sent');
  }

  Future<void> _onSignalingMessage(RtcMessage message) async {
    if (message.roomId != chatId) return;
    switch (message.type) {
      case RtcMessageType.offer:
        if (isCaller) {
          debugPrint(
              '[stealth-call] caller received unexpected offer; ignored');
          return;
        }
        final sdp = RTCSessionDescription(
          message.payload['sdp'] as String?,
          message.payload['type'] as String?,
        );
        await _applyRemoteOffer(sdp);
        break;
      case RtcMessageType.answer:
        await _handleAnswer(message);
        break;
      case RtcMessageType.candidate:
        await _handleRemoteCandidate(message);
        break;
      case RtcMessageType.hangup:
        await _handleRemoteHangup(message);
        break;
    }
  }

  Future<void> _handleAnswer(RtcMessage message) async {
    final sdp = message.payload['sdp'] as String?;
    final type = message.payload['type'] as String?;
    if (sdp == null || type == null) return;
    await media.applyRemoteAnswer(RTCSessionDescription(sdp, type));
  }

  Future<void> _handleRemoteCandidate(RtcMessage message) async {
    final payload = message.payload;
    final candidate = RTCIceCandidate(
      payload['candidate'] as String?,
      payload['sdpMid'] as String?,
      payload['sdpMLineIndex'] as int?,
    );
    await media.addOrBufferRemoteCandidate(candidate);
  }

  /// Обрабатывает hangup от пира. Закрываем экран сразу (вместо ожидания
  /// ICE timeout 15+ секунд), не пытаемся ещё раз слать sendHangup —
  /// инициатор уже знает.
  Future<void> _handleRemoteHangup(RtcMessage message) async {
    debugPrint(
      '[stealth-call] remote hangup → closing screen '
      'roomId=${message.roomId} from=${message.creator}',
    );
    if (_closing) return;
    _closing = true;
    onClose?.call();
  }

  void _markConnected() {
    if (!_connected) {
      _startTimer();
      media.startStatsLogger();
      // Принудительно применяем аудио-роутинг при первом коннекте.
      // Без этого Android оставляет вывод в earpiece (а на эмуляторе
      // earpiece часто не озвучен), и собеседника не слышно даже когда
      // RTP-пакеты идут.
      // ignore: discarded_futures
      media.applyAudioRouting();
    }
    _connectionTimeout?.cancel();
    _connected = true;
    _initializing = false;
    notifyListeners();
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  void toggleMicrophone() {
    _microphoneEnabled = !_microphoneEnabled;
    media.setMicrophoneEnabled(_microphoneEnabled);
    notifyListeners();
  }

  void toggleCamera() {
    _cameraEnabled = !_cameraEnabled;
    media.setCameraEnabled(_cameraEnabled);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await media.switchCamera();
  }

  Future<void> toggleSpeaker() async {
    _speakerEnabled = !_speakerEnabled;
    notifyListeners();
    await media.setSpeakerphoneOn(_speakerEnabled);
  }

  Future<void> hangUp() async {
    Logger.info('[stealth-call] hangUp()', extras: {
      'isCaller': isCaller,
      'connected': _connected,
      'closing': _closing,
    });
    if (_closing) return;
    _closing = true;
    final target = _targetUserId;
    if (target != null) {
      try {
        await _signaling?.sendHangup(
          roomId: chatId,
          targetUserId: target,
        );
      } catch (error) {
        debugPrint('[stealth-call] sendHangup error: $error');
      }
    }
    onClose?.call();
  }

  @override
  void dispose() {
    debugPrint(
      '[stealth-call] dispose() isCaller=$isCaller '
      'chat=$chatId connected=$_connected closing=$_closing',
    );
    _connectionTimeout?.cancel();
    _callTimer?.cancel();
    // ignore: discarded_futures
    _signalingSub?.cancel();
    // ignore: discarded_futures
    _signaling?.disconnect();
    // ignore: discarded_futures
    media.dispose();
    super.dispose();
  }
}
