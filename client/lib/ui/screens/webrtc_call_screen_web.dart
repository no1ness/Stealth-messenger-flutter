import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stealth/services/signaling/peer_resolver.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';
import 'package:stealth/webrtc_support.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';
import 'package:web/web.dart' as web;

class WebRTCCallScreen extends StatefulWidget {
  final String peerName;
  final String chatId;
  final bool isCaller;
  final bool isVideoCall;

  /// Уже принятый offer от другого пира (Map с ключами `sdp` и `type`).
  /// Передаётся `CallManager` callee'у при открытии экрана, чтобы избежать
  /// race condition подписки. Для caller всегда `null`.
  final Map<String, dynamic>? initialOffer;

  /// UUID звонящего; заполняется только для callee.
  final String? callerUserId;

  const WebRTCCallScreen({
    super.key,
    required this.peerName,
    required this.chatId,
    required this.isCaller,
    this.isVideoCall = false,
    this.initialOffer,
    this.callerUserId,
  });

  @override
  State<WebRTCCallScreen> createState() => _WebRTCCallScreenState();
}

class _WebRTCCallScreenState extends State<WebRTCCallScreen> {
  static final Set<String> _registeredViewTypes = <String>{};

  /// Используется только для получения selfUserId/nickname. Сигналинг
  /// идёт через [_signaling].
  final LocalAppService _appService = LocalAppService();

  /// Создаётся лениво в [_startCall]. См. комментарий в native-имплементации
  /// `webrtc_call_screen_native_impl.dart` — конструктор по умолчанию
  /// синхронно читает `dotenv.env['POCKETBASE_URL']`, что в widget-тестах
  /// без загруженного `.env` падает в field-init State и блокирует рендер.
  WebRtcSignalingService? _signaling;
  final PeerResolver _peerResolver = PeerResolver();
  final List<web.RTCIceCandidateInit> _pendingRemoteCandidates =
      <web.RTCIceCandidateInit>[];

  web.RTCPeerConnection? _peerConnection;
  web.MediaStream? _localStream;
  web.MediaStream? _remoteStream;
  web.HTMLAudioElement? _remoteAudioElement;
  web.HTMLVideoElement? _remoteVideoElement;
  web.HTMLVideoElement? _localVideoElement;
  Timer? _connectionTimeout;
  Timer? _callTimer;
  Timer? _audioAuditTimer;
  StreamSubscription<RtcMessage>? _signalingSub;

  String? _selfUserId;
  String? _targetUserId;

  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = true;
  bool _initializing = true;
  bool _connected = false;
  bool _offerSent = false;
  bool _startRequested = false;
  bool _closing = false;
  int _callDurationSeconds = 0;
  String _signalingState = 'stable';
  String _iceConnectionState = 'new';
  String _connectionState = 'new';
  String? _setupError;
  late final String _remoteViewType;
  late final String _localViewType;

  @override
  void initState() {
    super.initState();
    _remoteViewType = 'stealth-remote-video-${widget.chatId.hashCode}';
    _localViewType = 'stealth-local-video-${widget.chatId.hashCode}';
    if (widget.isVideoCall) {
      _initVideoElements();
    }
    _startCall();
  }

  void _registerViewType(String viewType, web.HTMLElement Function(int) factory) {
    if (_registeredViewTypes.contains(viewType)) return;
    ui_web.platformViewRegistry.registerViewFactory(viewType, factory);
    _registeredViewTypes.add(viewType);
  }

  void _initVideoElements() {
    _remoteVideoElement = web.HTMLVideoElement()
      ..autoplay = true
      ..playsInline = true
      ..muted = !_speakerEnabled
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';
    _localVideoElement = web.HTMLVideoElement()
      ..autoplay = true
      ..playsInline = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';
    _registerViewType(_remoteViewType, (_) => _remoteVideoElement!);
    _registerViewType(_localViewType, (_) => _localVideoElement!);
  }

  @override
  void dispose() {
    debugPrint(
      '[stealth-call] web dispose() isCaller=${widget.isCaller} '
      'chat=${widget.chatId} connected=$_connected closing=$_closing',
    );
    _connectionTimeout?.cancel();
    _callTimer?.cancel();
    _audioAuditTimer?.cancel();
    // ignore: discarded_futures
    _signalingSub?.cancel();
    // ignore: discarded_futures
    _signaling?.disconnect();
    _disposeMedia();
    super.dispose();
  }

  Future<void> _startCall() async {
    if (_startRequested) {
      return;
    }
    _startRequested = true;
    try {
      final support = await getWebRTCSupport();
      if (!support.isSupported) {
        throw Exception(support.blockingIssues.join(' '));
      }

      // Создаём signaling лениво — после WebRTC support gate. Не в field-init,
      // чтобы widget-тесты без dotenv не падали на PocketBaseClient.instance.
      debugPrint('[FIX] webrtc-call web: lazy WebRtcSignalingService init');
      _signaling = WebRtcSignalingService();

      _selfUserId = await _appService.getUserId();
      if (_selfUserId == null) {
        throw StateError('Cannot start call: missing local user id');
      }
      if (widget.isCaller) {
        _targetUserId = await _peerResolver.resolveTarget(
          chatId: widget.chatId,
          selfUserId: _selfUserId!,
        );
      } else {
        _targetUserId = widget.callerUserId;
        if (_targetUserId == null) {
          throw StateError('Callee opened without callerUserId');
        }
      }
      debugPrint(
        '[stealth-call] web using signaling=PocketBase '
        'self=$_selfUserId target=$_targetUserId isCaller=${widget.isCaller}',
      );

      await _createPeerConnection();
      await _createLocalStream();
      await _attachLocalAudio();

      await _signaling!.connect(
        roomId: widget.chatId,
        selfUserId: _selfUserId!,
      );
      _signalingSub = _signaling!.incoming.listen(_onSignalingMessage);

      _connectionTimeout = Timer(const Duration(seconds: 120), () {
        if (!_connected && mounted) {
          debugPrint('[stealth-call] web connection timeout fired');
          _showSnackBar('Connection timed out.');
          _hangUp();
        }
      });

      if (widget.isCaller) {
        debugPrint('[stealth-call] web caller — creating offer immediately');
        await _createOffer();
      } else {
        final offerMap = widget.initialOffer;
        if (offerMap != null) {
          debugPrint('[stealth-call] web callee — applying initialOffer');
          await _applyRemoteOffer(offerMap);
        } else {
          debugPrint(
            '[stealth-call] web callee — waiting for offer via signaling',
          );
        }
      }

      if (mounted) {
        setState(() {
          _initializing = false;
          _setupError = null;
        });
      }
    } catch (error) {
      debugPrint('Web call init error: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _initializing = false;
        _setupError = 'Call setup failed: $error';
      });
      _showSnackBar('Call setup failed.');
    }
  }

  Future<void> _retrySetup() async {
    // ignore: discarded_futures
    _signalingSub?.cancel();
    _signalingSub = null;
    _disposeMedia();
    await _signaling?.disconnect();
    _signaling = null;
    _pendingRemoteCandidates.clear();
    if (!mounted) {
      return;
    }

    setState(() {
      _initializing = true;
      _connected = false;
      _offerSent = false;
      _startRequested = false;
      _closing = false;
      _callDurationSeconds = 0;
      _signalingState = 'stable';
      _iceConnectionState = 'new';
      _connectionState = 'new';
      _setupError = null;
    });
    await _startCall();
  }

  void _appendWebTurnServer(
    List<web.RTCIceServer> servers, {
    required String label,
    required String? urlsEnv,
    required String? userEnv,
    required String? passEnv,
  }) {
    final raw = urlsEnv?.trim();
    if (raw == null || raw.isEmpty) return;
    final urls = raw
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .map((u) => u.toJS)
        .toList()
        .toJS;
    servers.add(
      web.RTCIceServer(
        urls: urls,
        username: userEnv?.trim() ?? '',
        credential: passEnv?.trim() ?? '',
      ),
    );
    debugPrint('[stealth-call] web $label configured: $raw');
  }

  Future<void> _createPeerConnection() async {
    final iceServers = <web.RTCIceServer>[
      web.RTCIceServer(
        urls: [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ].map((u) => u.toJS).toList().toJS,
      ),
    ];
    _appendWebTurnServer(
      iceServers,
      label: 'TURN',
      urlsEnv: dotenv.env['TURN_URL'],
      userEnv: dotenv.env['TURN_USERNAME'],
      passEnv: dotenv.env['TURN_PASSWORD'],
    );
    _appendWebTurnServer(
      iceServers,
      label: 'TURNS',
      urlsEnv: dotenv.env['TURNS_URL'],
      userEnv: dotenv.env['TURNS_USERNAME'],
      passEnv: dotenv.env['TURNS_PASSWORD'],
    );
    if (iceServers.length == 1) {
      debugPrint(
        '[stealth-call] web: no TURN/TURNS in .env — P2P may fail across NAT',
      );
    }
    final configuration = web.RTCConfiguration(
      iceServers: iceServers.toJS,
      iceCandidatePoolSize: 4,
    );

    final peerConnection = web.RTCPeerConnection(configuration);
    _peerConnection = peerConnection;

    // Browser WebRTC uses DOM events instead of flutter_webrtc callbacks.
    peerConnection.onicecandidate = ((web.Event event) {
      final iceEvent = event as web.RTCPeerConnectionIceEvent;
      final candidate = iceEvent.candidate;
      if (candidate == null || candidate.candidate.isEmpty) {
        return;
      }
      final target = _targetUserId;
      if (target == null) return;
      // ignore: discarded_futures
      _signaling?.sendCandidate(
        roomId: widget.chatId,
        targetUserId: target,
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    }).toJS;

    peerConnection.ontrack = ((web.Event event) {
      final trackEvent = event as web.RTCTrackEvent;

      final streams = trackEvent.streams.toDart;
      if (streams.isNotEmpty) {
        unawaited(_attachRemoteStream(streams.first));
        return;
      }

      final fallback = _remoteStream ?? web.MediaStream();
      fallback.addTrack(trackEvent.track);
      unawaited(_attachRemoteStream(fallback));
    }).toJS;

    peerConnection.oniceconnectionstatechange = ((web.Event event) {
      final state = peerConnection.iceConnectionState;
      debugPrint('[stealth-call] web iceState=$state');
      if (mounted) {
        setState(() => _iceConnectionState = state);
      }
      if (state == 'connected' || state == 'completed') {
        _markConnected();
      } else if (state == 'failed') {
        debugPrint('[stealth-call] web ICE failed — calling _hangUp');
        _showSnackBar('Connection failed.');
        _hangUp();
      }
    }).toJS;

    peerConnection.onsignalingstatechange = ((web.Event event) {
      if (mounted) {
        setState(() => _signalingState = peerConnection.signalingState);
      }
    }).toJS;

    peerConnection.onconnectionstatechange = ((web.Event event) {
      final state = peerConnection.connectionState;
      debugPrint('[stealth-call] web peerState=$state');
      if (mounted) {
        setState(() => _connectionState = state);
      }
    }).toJS;
  }

  Future<void> _createLocalStream() async {
    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(
          web.MediaStreamConstraints(
            audio: {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            }.jsify() as JSAny,
            video: widget.isVideoCall
                ? {
                    'facingMode': 'user',
                    'width': {'ideal': 640},
                    'height': {'ideal': 480},
                  }.jsify() as JSAny
                : false.toJS,
          ),
        )
        .toDart;
    _localStream = stream;
    if (widget.isVideoCall && _localVideoElement != null) {
      _localVideoElement!.srcObject = stream;
      unawaited(_playLocalPreview());
    }
  }

  Future<void> _playLocalPreview() async {
    final element = _localVideoElement;
    if (element == null) return;
    try {
      await element.play().toDart;
    } catch (_) {
      // ignore autoplay-related errors, browser may require user gesture.
    }
  }

  Future<void> _attachLocalAudio() async {
    final connection = _peerConnection;
    final stream = _localStream;
    if (connection == null || stream == null) {
      return;
    }

    final audioTracks = stream.getAudioTracks().toDart;
    if (audioTracks.isEmpty) {
      throw Exception('No microphone track available.');
    }

    for (final track in audioTracks) {
      connection.addTrack(track, stream);
    }
    if (widget.isVideoCall) {
      final videoTracks = stream.getVideoTracks().toDart;
      for (final track in videoTracks) {
        connection.addTrack(track, stream);
      }
    }
  }

  Future<void> _createOffer() async {
    final connection = _peerConnection;
    final target = _targetUserId;
    if (connection == null || target == null || _offerSent) {
      return;
    }

    try {
      final offer = await connection
          .createOffer(
            web.RTCOfferOptions(
              offerToReceiveAudio: true,
              offerToReceiveVideo: widget.isVideoCall,
            ),
          )
          .toDart;
      if (offer == null) {
        return;
      }
      await connection
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(
              type: offer.type,
              sdp: offer.sdp,
            ),
          )
          .toDart;
      final nickname = await _appService.getNickname();
      await _signaling!.sendOffer(
        roomId: widget.chatId,
        targetUserId: target,
        sdp: {
          'type': offer.type,
          'sdp': offer.sdp,
          'purpose': 'call',
          'nickname': nickname ?? '',
          'callType': widget.isVideoCall ? 'video' : 'audio',
        },
      );
      _offerSent = true;
    } catch (error) {
      debugPrint('Offer creation error: $error');
    }
  }

  /// Применяет уже принятый offer (от `IncomingCallSignalingService`).
  Future<void> _applyRemoteOffer(Map<String, dynamic> offerMap) async {
    final connection = _peerConnection;
    final target = _targetUserId;
    if (connection == null || target == null) {
      return;
    }
    final sdp = offerMap['sdp'] as String?;
    final type = offerMap['type'] as String?;
    if (sdp == null || type == null) return;

    try {
      await connection
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(type: type, sdp: sdp),
          )
          .toDart;
      await _flushPendingCandidates();
      final answer = await connection.createAnswer().toDart;
      if (answer == null) return;
      await connection
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(
              type: answer.type,
              sdp: answer.sdp,
            ),
          )
          .toDart;
      await _signaling!.sendAnswer(
        roomId: widget.chatId,
        targetUserId: target,
        sdp: {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      );
      debugPrint('[stealth-call] web answer sent');
    } catch (error) {
      debugPrint('Web applyRemoteOffer error: $error');
    }
  }

  /// Единая точка входа для входящих сигнальных сообщений. Server-side
  /// фильтр уже отбросил собственные echo по target=self.
  Future<void> _onSignalingMessage(RtcMessage message) async {
    if (message.roomId != widget.chatId) return;
    switch (message.type) {
      case RtcMessageType.offer:
        if (widget.isCaller) {
          debugPrint('[stealth-call] web caller received unexpected offer; ignored');
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
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }
    final sdp = message.payload['sdp'] as String?;
    final type = message.payload['type'] as String?;
    if (sdp == null || type == null) return;

    try {
      await connection
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(type: type, sdp: sdp),
          )
          .toDart;
      await _flushPendingCandidates();
    } catch (error) {
      debugPrint('Answer handling error: $error');
    }
  }

  Future<void> _handleRemoteCandidate(RtcMessage message) async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }

    try {
      final payload = message.payload;
      final candidate = web.RTCIceCandidateInit(
        candidate: payload['candidate'] as String,
        sdpMid: payload['sdpMid'] as String?,
        sdpMLineIndex: payload['sdpMLineIndex'] as int?,
      );
      if (connection.remoteDescription != null) {
        await connection.addIceCandidate(candidate).toDart;
      } else {
        _pendingRemoteCandidates.add(candidate);
      }
    } catch (error) {
      debugPrint('Remote candidate error: $error');
    }
  }

  /// Hangup от пира — закрываем экран без повторной отправки sendHangup.
  Future<void> _handleRemoteHangup(RtcMessage message) async {
    debugPrint(
      '[stealth-call] web remote hangup → closing screen '
      'roomId=${message.roomId} from=${message.creator}',
    );
    if (_closing) return;
    _closing = true;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _flushPendingCandidates() async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }

    for (final candidate in _pendingRemoteCandidates) {
      await connection.addIceCandidate(candidate).toDart;
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> _attachRemoteStream(web.MediaStream stream) async {
    _remoteStream = stream;
    if (widget.isVideoCall && _remoteVideoElement != null) {
      _remoteVideoElement!
        ..muted = !_speakerEnabled
        ..srcObject = stream;
      try {
        await _remoteVideoElement!.play().toDart;
      } catch (_) {
        // ignore autoplay-related errors, browser may require user gesture.
      }
    } else {
      _remoteAudioElement ??= web.HTMLAudioElement()
        ..autoplay = true
        ..muted = !_speakerEnabled;

      final audioElement = _remoteAudioElement!;
      audioElement.srcObject = stream;
      audioElement.style.display = 'none';
      if (audioElement.parentNode == null) {
        web.document.body?.append(audioElement);
      }

      try {
        await audioElement.play().toDart;
      } catch (_) {
        // Browsers may delay autoplay until the first user gesture.
      }
    }
    debugPrint(
      '[stealth-call] web remote stream attached, '
      'audio=${stream.getAudioTracks().toDart.length} '
      'video=${stream.getVideoTracks().toDart.length}',
    );
  }

  void _markConnected() {
    if (!mounted) {
      return;
    }
    if (!_connected) {
      _startTimer();
      _startAudioAudit();
    }
    _connectionTimeout?.cancel();
    setState(() {
      _connected = true;
      _initializing = false;
    });
  }

  /// Периодически проверяем состояние аудио-треков, чтобы убедиться что
  /// звук действительно идёт. Вывод виден в DevTools → Console.
  void _startAudioAudit() {
    Timer.periodic(const Duration(seconds: 2), (_) {
      final remote = _remoteStream;
      if (remote == null) return;
      final audioTracks = remote.getAudioTracks().toDart;
      for (final track in audioTracks) {
        debugPrint(
          '[stealth-audio-audit] remote audio track id=${track.id} '
          'kind=${track.kind} readyState=${track.readyState} '
          'enabled=${track.enabled} muted=${track.muted} '
          'label=${track.label}',
        );
      }
      final local = _localStream;
      if (local == null) return;
      final localAudio = local.getAudioTracks().toDart;
      for (final track in localAudio) {
        debugPrint(
          '[stealth-audio-audit] local audio track id=${track.id} '
          'readyState=${track.readyState} enabled=${track.enabled} '
          'muted=${track.muted} label=${track.label}',
        );
      }
    });
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _callDurationSeconds++);
    });
  }

  void _toggleMicrophone() {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    for (final track in stream.getAudioTracks().toDart) {
      track.enabled = !track.enabled;
    }
    setState(() => _microphoneEnabled = !_microphoneEnabled);
  }

  void _toggleSpeaker() {
    final videoElement = _remoteVideoElement;
    if (videoElement != null) {
      videoElement.muted = _speakerEnabled;
    }
    final audioElement = _remoteAudioElement;
    if (audioElement != null) {
      audioElement.muted = _speakerEnabled;
    }
    setState(() => _speakerEnabled = !_speakerEnabled);
  }

  void _toggleCamera() {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks().toDart) {
      track.enabled = !track.enabled;
    }
    setState(() => _cameraEnabled = !_cameraEnabled);
  }

  Future<void> _hangUp() async {
    debugPrint(
      '[stealth-call] web _hangUp() isCaller=${widget.isCaller} '
      'connected=$_connected closing=$_closing '
      'stack=${StackTrace.current.toString().split("\n").take(6).join(" | ")}',
    );
    if (_closing) {
      return;
    }
    _closing = true;
    _disposeMedia();
    final target = _targetUserId;
    if (target != null) {
      try {
        await _signaling?.sendHangup(
          roomId: widget.chatId,
          targetUserId: target,
        );
      } catch (error) {
        debugPrint('[stealth-call] web sendHangup error: $error');
      }
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _disposeMedia() {
    for (final track in _localStream?.getTracks().toDart ?? const []) {
      track.stop();
    }
    for (final track in _remoteStream?.getTracks().toDart ?? const []) {
      track.stop();
    }
    _remoteAudioElement?.pause();
    _remoteAudioElement?.remove();
    _remoteAudioElement = null;
    _remoteVideoElement?.pause();
    _remoteVideoElement = null;
    _localVideoElement?.pause();
    _localVideoElement = null;
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        debugPrint(
          '[stealth-call] web PopScope didPop=$didPop isCaller=${widget.isCaller} '
          'connected=$_connected closing=$_closing',
        );
        if (!didPop) {
          await _hangUp();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: StealthAnimatedBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                        ),
                        onPressed: _hangUp,
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Browser WebRTC',
                        style: AppTypography.caption1.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                const Spacer(),
                if (widget.isVideoCall)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        height: 260,
                        color: Colors.black.withValues(alpha: 0.35),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_remoteStream != null &&
                                _remoteStream!.getVideoTracks().toDart.isNotEmpty)
                              HtmlElementView(viewType: _remoteViewType)
                            else
                              Center(
                                child: Text(
                                  'Waiting for video...',
                                  style: AppTypography.body.copyWith(color: Colors.white70),
                                ),
                              ),
                            Positioned(
                              right: 12,
                              top: 12,
                              child: SizedBox(
                                width: 100,
                                height: 140,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    color: Colors.black54,
                                    child: (_localStream != null &&
                                            _localStream!.getVideoTracks().toDart.isNotEmpty)
                                        ? HtmlElementView(viewType: _localViewType)
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.glassLight.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppColors.glassLight.withValues(alpha: 0.2),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.systemBlue.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        widget.peerName.isNotEmpty
                            ? widget.peerName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  widget.peerName,
                  style: AppTypography.largeTitle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _connected
                      ? _formatDuration(_callDurationSeconds)
                      : _initializing
                          ? 'Connecting...'
                          : 'Calling...',
                  style: AppTypography.body.copyWith(
                    color: _connected
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_setupError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        Text(
                          _setupError!,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            color: AppColors.systemRed,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.md,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: _retrySetup,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const WebRTCDiagnosticsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.network_check),
                              label: const Text('Diagnostics'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildStatusChip(
                      label: _connected ? 'Connected' : 'Negotiating',
                      active: _connected,
                    ),
                    _buildStatusChip(
                      label: _microphoneEnabled ? 'Mic on' : 'Mic muted',
                      active: _microphoneEnabled,
                    ),
                    _buildStatusChip(
                      label: _speakerEnabled ? 'Speaker on' : 'Speaker off',
                      active: _speakerEnabled,
                    ),
                    _buildStatusChip(
                      label: 'ICE: $_iceConnectionState',
                      active: _iceConnectionState == 'connected' ||
                          _iceConnectionState == 'completed',
                    ),
                    _buildStatusChip(
                      label: 'Signal: $_signalingState',
                      active: _signalingState == 'stable',
                    ),
                    _buildStatusChip(
                      label: 'Peer: $_connectionState',
                      active: _connectionState == 'connected',
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (widget.isVideoCall)
                        _buildControlButton(
                          icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                          color: _cameraEnabled
                              ? Colors.white.withValues(alpha: 0.2)
                              : Colors.white,
                          iconColor: _cameraEnabled ? Colors.white : Colors.black,
                          onPressed: _toggleCamera,
                        ),
                      _buildControlButton(
                        icon: _microphoneEnabled ? Icons.mic : Icons.mic_off,
                        color: _microphoneEnabled
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.white,
                        iconColor: _microphoneEnabled
                            ? Colors.white
                            : Colors.black,
                        onPressed: _toggleMicrophone,
                      ),
                      _buildControlButton(
                        icon: Icons.call_end,
                        color: AppColors.systemRed,
                        iconColor: Colors.white,
                        size: 72,
                        onPressed: _hangUp,
                      ),
                      _buildControlButton(
                        icon: _speakerEnabled
                            ? Icons.volume_up
                            : Icons.volume_off,
                        color: _speakerEnabled
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.white,
                        iconColor: _speakerEnabled
                            ? Colors.white
                            : Colors.black,
                        onPressed: _toggleSpeaker,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onPressed,
    double size = 56,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({required String label, required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: active
            ? AppColors.systemGreen.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? AppColors.systemGreen.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.caption1.copyWith(
          color: active ? AppColors.systemGreen : Colors.white,
        ),
      ),
    );
  }
}
