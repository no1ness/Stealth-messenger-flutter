import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/peer_resolver.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/signaling_transport.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/ui/screens/calls/web_call_media_bindings.dart';
import 'package:stealth/webrtc_support.dart';

typedef SignalingBuilder = SignalingTransport Function();

/// Контроллер web-варианта `WebRTCCallScreen`. Зеркальный API с
/// `NativeCallController`, отличается только web-specific media (DOM API)
/// и дополнительными состояниями `signalingState/iceConnectionState/
/// connectionState/setupError` + `retry()`.
class WebCallController extends ChangeNotifier {
  WebCallController({
    required this.chatId,
    required this.isCaller,
    required this.isVideoCall,
    this.initialOffer,
    this.callerUserId,
    WebCallMediaBindings? media,
    LocalAppService? appService,
    PeerResolver? peerResolver,
    SignalingBuilder? signalingBuilder,
    this.onError,
    this.onClose,
  })  : media = media ?? WebCallMediaBindings(),
        _appService = appService ?? LocalAppService(),
        _peerResolver = peerResolver ?? PeerResolver(),
        _signalingBuilder =
            signalingBuilder ?? (() => WebRtcSignalingService()) {
    remoteViewType = 'stealth-remote-video-${chatId.hashCode}';
    localViewType = 'stealth-local-video-${chatId.hashCode}';
  }

  final String chatId;
  final bool isCaller;
  final bool isVideoCall;
  final Map<String, dynamic>? initialOffer;
  final String? callerUserId;

  final WebCallMediaBindings media;
  final LocalAppService _appService;
  final PeerResolver _peerResolver;
  final SignalingBuilder _signalingBuilder;

  final void Function(String message)? onError;
  final VoidCallback? onClose;

  late final String remoteViewType;
  late final String localViewType;

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
  String _signalingState = 'stable';
  String _iceConnectionState = 'new';
  String _connectionState = 'new';
  String? _setupError;

  bool get microphoneEnabled => _microphoneEnabled;
  bool get cameraEnabled => _cameraEnabled;
  bool get speakerEnabled => _speakerEnabled;
  bool get initializing => _initializing;
  bool get connected => _connected;
  bool get closing => _closing;
  int get callDurationSeconds => _callDurationSeconds;
  String get signalingState => _signalingState;
  String get iceConnectionState => _iceConnectionState;
  String get connectionState => _connectionState;
  String? get setupError => _setupError;
  String? get selfUserId => _selfUserId;
  String? get targetUserId => _targetUserId;

  Future<void> initialize() async {
    if (_startRequested) return;
    _startRequested = true;
    try {
      final support = await getWebRTCSupport();
      if (!support.isSupported) {
        throw Exception(support.blockingIssues.join(' '));
      }

      Logger.debug('[stealth-call] web lazy WebRtcSignalingService init');
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
      Logger.info(
        '[stealth-call] web using signaling=PocketBase',
        extras: {
          'selfUserId': _selfUserId,
          'targetUserId': _targetUserId,
          'isCaller': isCaller,
        },
      );

      if (isVideoCall) {
        media.initVideoElements(
          remoteViewType: remoteViewType,
          localViewType: localViewType,
        );
      }

      await media.createPeerConnection(
        isVideoCall: isVideoCall,
        onLocalCandidate: _handleLocalCandidate,
        onRemoteStreamReady: (_) async => notifyListeners(),
        onIceConnectionState: _handleIceConnectionState,
        onSignalingState: (state) {
          _signalingState = state;
          notifyListeners();
        },
        onConnectionState: (state) {
          _connectionState = state;
          notifyListeners();
        },
      );
      await media.createLocalStream(isVideoCall: isVideoCall);
      await media.attachLocalAudio(isVideoCall: isVideoCall);

      await _signaling!.connect(
        roomId: chatId,
        selfUserId: _selfUserId!,
        peerUserIds: _targetUserId == null ? const [] : [_targetUserId!],
      );
      _signalingSub = _signaling!.incoming.listen(_onSignalingMessage);

      _connectionTimeout = Timer(const Duration(seconds: 120), () {
        if (!_connected) {
          Logger.warn('[stealth-call] web connection timeout fired');
          onError?.call('Connection timed out.');
          hangUp();
        }
      });

      if (isCaller) {
        Logger.debug('[stealth-call] web caller creating offer immediately');
        await _sendOffer();
      } else {
        final offerMap = initialOffer;
        if (offerMap != null) {
          Logger.debug('[stealth-call] web callee applying initialOffer');
          await _applyRemoteOffer(offerMap);
        } else {
          Logger.debug('[stealth-call] web callee waiting for offer via signaling');
        }
      }

      _initializing = false;
      _setupError = null;
      notifyListeners();
    } catch (error) {
      Logger.error('[stealth-call] web call init error', extras: {'error': error});
      _initializing = false;
      _setupError = 'Call setup failed: $error';
      notifyListeners();
      onError?.call('Call setup failed.');
    }
  }

  /// Полный reset и повторный `initialize()` — используется кнопкой Retry
  /// на экране ошибки настройки.
  Future<void> retry() async {
    // ignore: discarded_futures
    _signalingSub?.cancel();
    _signalingSub = null;
    await media.dispose();
    media.resetForRetry();
    await _signaling?.disconnect();
    _signaling = null;

    _initializing = true;
    _connected = false;
    _closing = false;
    _startRequested = false;
    _callDurationSeconds = 0;
    _signalingState = 'stable';
    _iceConnectionState = 'new';
    _connectionState = 'new';
    _setupError = null;
    notifyListeners();
    await initialize();
  }

  void _handleLocalCandidate(Map<String, dynamic> candidate) {
    final target = _targetUserId;
    if (target == null) return;
    // ignore: discarded_futures
    _signaling?.sendCandidate(
      roomId: chatId,
      targetUserId: target,
      candidate: candidate,
    );
  }

  void _handleIceConnectionState(String state) {
    _iceConnectionState = state;
    notifyListeners();
    if (state == 'connected' || state == 'completed') {
      _markConnected();
    } else if (state == 'failed') {
      Logger.warn('[stealth-call] web ICE failed, calling hangUp');
      onError?.call('Connection failed.');
      hangUp();
    }
  }

  Future<void> _sendOffer() async {
    final payload = await media.createLocalOffer(isVideoCall: isVideoCall);
    final target = _targetUserId;
    if (payload == null || target == null) return;
    final nickname = await _appService.getNickname();
    await _signaling!.sendOffer(
      roomId: chatId,
      targetUserId: target,
      sdp: {
        ...payload,
        'purpose': 'call',
        'nickname': nickname ?? '',
        'callType': isVideoCall ? 'video' : 'audio',
      },
    );
  }

  Future<void> _applyRemoteOffer(Map<String, dynamic> offerMap) async {
    final answer = await media.applyRemoteOffer(offerMap);
    final target = _targetUserId;
    if (answer == null || target == null) return;
    await _signaling!.sendAnswer(
      roomId: chatId,
      targetUserId: target,
      sdp: answer,
    );
    Logger.info('[stealth-call] web answer sent');
  }

  Future<void> _onSignalingMessage(RtcMessage message) async {
    if (message.roomId != chatId) return;
    switch (message.type) {
      case RtcMessageType.offer:
        if (isCaller) {
          Logger.warn(
            '[stealth-call] web caller received unexpected offer; ignored',
          );
          return;
        }
        await _applyRemoteOffer(message.payload);
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
    await media.applyRemoteAnswer(type: type, sdp: sdp);
  }

  Future<void> _handleRemoteCandidate(RtcMessage message) async {
    await media.addOrBufferRemoteCandidate(message.payload);
  }

  Future<void> _handleRemoteHangup(RtcMessage message) async {
    Logger.info(
      '[stealth-call] web remote hangup, closing screen',
      extras: {'roomId': message.roomId, 'fromUserId': message.creator},
    );
    if (_closing) return;
    _closing = true;
    onClose?.call();
  }

  void _markConnected() {
    if (!_connected) {
      _startTimer();
      media.startAudioAudit();
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

  void toggleSpeaker() {
    _speakerEnabled = !_speakerEnabled;
    media.setSpeakerphoneOn(_speakerEnabled);
    notifyListeners();
  }

  Future<void> hangUp() async {
    Logger.info('[stealth-call] web hangUp()', extras: {
      'isCaller': isCaller,
      'connected': _connected,
      'closing': _closing,
    });
    if (_closing) return;
    _closing = true;
    // Web: dispose media сразу (закрывает PC и треки) — оригинальное поведение
    // отрезает RTP до того, как onClose реально снимет экран с фокуса.
    await media.dispose();
    final target = _targetUserId;
    if (target != null) {
      try {
        await _signaling?.sendHangup(
          roomId: chatId,
          targetUserId: target,
        );
      } catch (error) {
        Logger.warn(
          '[stealth-call] web sendHangup error',
          extras: {'error': error},
        );
      }
    }
    onClose?.call();
  }

  @override
  void dispose() {
    Logger.debug(
      '[stealth-call] web dispose',
      extras: {
        'isCaller': isCaller,
        'chatId': chatId,
        'connected': _connected,
        'closing': _closing,
      },
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
