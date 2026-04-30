import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stealth/services/signaling/peer_resolver.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';
import 'package:stealth/constants/accessibility_ids.dart';

class WebRTCCallScreen extends StatefulWidget {
  final String peerName;
  final String chatId;
  final bool isCaller;
  final bool isVideoCall;

  /// Уже принятый offer от другого пира как plain Map с ключами `sdp`
  /// и `type`. Передаётся `CallManager` при открытии экрана callee,
  /// чтобы избежать race condition подписки. Для caller всегда `null`.
  ///
  /// Map (а не `RTCSessionDescription`) выбран для совместимости с
  /// web-имплементацией, которая не использует `flutter_webrtc`.
  final Map<String, dynamic>? initialOffer;

  /// UUID звонящего (caller). Заполняется только для callee — для caller
  /// определяется через `PeerResolver`. Используется как `targetUserId`
  /// при отправке answer/ICE/hangup.
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
  /// Используется ТОЛЬКО для получения локального selfUserId / nickname.
  /// Сигналинг идёт через [_signaling], не через Supabase.
  final SupabaseService _supabaseService = SupabaseService();
  final WebRtcSignalingService _signaling = WebRtcSignalingService();
  final PeerResolver _peerResolver = PeerResolver();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  Timer? _connectionTimeout;
  Timer? _callTimer;
  Timer? _statsTimer;
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

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  @override
  void dispose() {
    debugPrint(
      '[stealth-call] dispose() isCaller=${widget.isCaller} '
      'chat=${widget.chatId} connected=$_connected closing=$_closing',
    );
    _connectionTimeout?.cancel();
    _callTimer?.cancel();
    _statsTimer?.cancel();
    // ignore: discarded_futures
    _signalingSub?.cancel();
    // ignore: discarded_futures
    _signaling.disconnect();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _disposeMedia();
    super.dispose();
  }

  Future<void> _startCall() async {
    if (_startRequested) return;
    _startRequested = true;
    try {
      if (!kIsWeb) {
        await _localRenderer.initialize();
        await _remoteRenderer.initialize();
      }
      final permissionsGranted =
          kIsWeb ? true : await _requestMicrophonePermission();
      if (!permissionsGranted) {
        if (!mounted) return;
        setState(() => _initializing = false);
        _showSnackBar('Microphone permission is required for calls.');
        Navigator.of(context).maybePop();
        return;
      }

      // Резолвим self и target до подписки. Для caller target резолвится
      // из локальной БД (PeerResolver), для callee — берётся из
      // widget.callerUserId, который проставил CallManager на основе
      // принятого offer.
      _selfUserId = await _supabaseService.getUserId();
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
        '[stealth-call] using signaling=PocketBase '
        'self=$_selfUserId target=$_targetUserId isCaller=${widget.isCaller}',
      );

      await _createPeerConnection();
      await _createLocalStream();
      await _attachLocalMedia();
      await _applyAudioRouting();

      // Подписываемся на сигналинг. PocketBase server-side фильтрует по
      // (roomId,target) — нам не нужно проверять `_isFromSelf`.
      await _signaling.connect(
        roomId: widget.chatId,
        selfUserId: _selfUserId!,
      );
      _signalingSub = _signaling.incoming.listen(_onSignalingMessage);

      _connectionTimeout = Timer(const Duration(seconds: 120), () {
        if (!_connected && mounted) {
          _showSnackBar('Connection timed out.');
          _hangUp();
        }
      });

      if (widget.isCaller) {
        // Caller сразу шлёт offer — гарантированной доставки добивается
        // тем, что PocketBase пишет запись в БД, а не bcast. Если callee
        // оффлайн — увидит offer как только подключится. На UI это
        // регулируется connectionTimeout (120 сек выше).
        debugPrint('[stealth-call] caller — creating offer immediately');
        await _createOffer();
      } else {
        // Callee. Если CallManager уже передал нам initialOffer —
        // обрабатываем его сразу, не дожидаясь повторной доставки через
        // подписку. Это устраняет race condition.
        final offerMap = widget.initialOffer;
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

      if (mounted) {
        setState(() => _initializing = false);
      }
    } catch (error) {
      debugPrint('WebRTC init error: $error');
      if (!mounted) return;
      setState(() => _initializing = false);
      _showSnackBar('Call setup failed: $error');
      Navigator.of(context).maybePop();
    }
  }

  /// Собирает список ICE-серверов. STUN идёт всегда. Дополнительно
  /// добавляются TURN (`TURN_URL`) и TURNS (`TURNS_URL`) — обе пары
  /// независимы, можно задать одну, обе или ни одной.
  ///
  /// TURNS на 443/TLS критичен для обхода ТСПУ в РФ: маскируется под
  /// обычный HTTPS. Без TURN/TURNS звонок между устройствами за symmetric
  /// NAT (мобильный интернет, VPN, эмулятор) не состоится.
  List<Map<String, dynamic>> _buildIceServers() {
    final servers = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];
    _appendTurnServer(
      servers,
      label: 'TURN',
      urlsEnv: dotenv.env['TURN_URL'],
      userEnv: dotenv.env['TURN_USERNAME'],
      passEnv: dotenv.env['TURN_PASSWORD'],
    );
    _appendTurnServer(
      servers,
      label: 'TURNS',
      urlsEnv: dotenv.env['TURNS_URL'],
      userEnv: dotenv.env['TURNS_USERNAME'],
      passEnv: dotenv.env['TURNS_PASSWORD'],
    );
    if (servers.length == 1) {
      debugPrint(
        '[stealth-call] WARNING: no TURN/TURNS in .env — P2P will fail across NAT/VPN. '
        'Set TURN_URL/TURN_USERNAME/TURN_PASSWORD or TURNS_URL/TURNS_USERNAME/TURNS_PASSWORD.',
      );
    }
    return servers;
  }

  void _appendTurnServer(
    List<Map<String, dynamic>> servers, {
    required String label,
    required String? urlsEnv,
    required String? userEnv,
    required String? passEnv,
  }) {
    final urls = urlsEnv?.trim();
    if (urls == null || urls.isEmpty) return;
    final user = userEnv?.trim();
    final pass = passEnv?.trim();
    servers.add({
      'urls': urls
          .split(',')
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .toList(),
      if (user != null && user.isNotEmpty) 'username': user,
      if (pass != null && pass.isNotEmpty) 'credential': pass,
    });
    debugPrint('[stealth-call] $label configured: $urls');
  }

  Future<bool> _requestMicrophonePermission() async {
    try {
      final microphoneStatus = await Permission.microphone.request();
      if (!microphoneStatus.isGranted) {
        if (!mounted) return false;
        _showSnackBar('Enable microphone access in settings.');
        return false;
      }
      if (widget.isVideoCall) {
        final cameraStatus = await Permission.camera.request();
        if (!cameraStatus.isGranted) {
          if (!mounted) return false;
          _showSnackBar('Enable camera access in settings.');
          return false;
        }
      }
      return true;
    } catch (error) {
      debugPrint('Permission request error: $error');
      return true;
    }
  }

  Future<void> _createPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': _buildIceServers(),
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 4,
      'iceTransportPolicy': 'all',
    };

    _peerConnection = await createPeerConnection(configuration, {
      'mandatory': <String, dynamic>{},
      'optional': <dynamic>[],
    });

    _peerConnection!.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      final target = _targetUserId;
      if (target == null) return;
      // ignore: discarded_futures
      _signaling.sendCandidate(
        roomId: widget.chatId,
        targetUserId: target,
        candidate: candidate.toMap(),
      );
    };

    _peerConnection!.onTrack = (event) async {
      debugPrint(
        '[stealth-call] onTrack kind=${event.track.kind} id=${event.track.id} '
        'enabled=${event.track.enabled} streams=${event.streams.length}',
      );
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        for (final track in stream.getTracks()) {
          track.enabled = true;
        }
        await _attachRemoteStream(stream, addedTrack: event.track);
        return;
      }
      final fallback = _remoteStream ?? await createLocalMediaStream('remote');
      if (!fallback.getTracks().any((track) => track.id == event.track.id)) {
        fallback.addTrack(event.track);
      }
      event.track.enabled = true;
      await _attachRemoteStream(fallback, addedTrack: event.track);
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('[stealth-call] iceState=$state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint('[stealth-call] ICE Connection Failed - triggering restart if possible');
        _showSnackBar('Connection failed. Retrying...');
        _hangUp();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        debugPrint('[stealth-call] ICE Connection Disconnected');
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('[stealth-call] peerState=$state');
    };
  }

  Future<void> _createLocalStream() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': widget.isVideoCall
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
    } catch (error) {
      debugPrint('[stealth-call] getUserMedia strict failed: $error, falling back');
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideoCall,
      });
    }
    final audioTracks = _localStream?.getAudioTracks() ?? const [];
    debugPrint(
      '[stealth-call] local stream ready: audio=${audioTracks.length} '
      'ids=${audioTracks.map((t) => t.id).toList()} '
      'enabled=${audioTracks.map((t) => t.enabled).toList()}',
    );
    if (_localStream != null && widget.isVideoCall) {
      _localRenderer.srcObject = _localStream;
    }
  }

  Future<void> _attachLocalMedia() async {
    final connection = _peerConnection;
    final stream = _localStream;
    if (connection == null || stream == null) return;
    final audioTracks = stream.getAudioTracks();
    if (audioTracks.isEmpty) throw Exception('No microphone track available.');
    for (final track in audioTracks) {
      await connection.addTrack(track, stream);
    }
    if (widget.isVideoCall) {
      final videoTracks = stream.getVideoTracks();
      for (final track in videoTracks) {
        await connection.addTrack(track, stream);
      }
    }
  }

  Future<void> _createOffer() async {
    final connection = _peerConnection;
    final target = _targetUserId;
    if (connection == null || target == null || _offerSent) return;
    try {
      final offer = await connection.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': widget.isVideoCall ? 1 : 0,
      });
      await connection.setLocalDescription(offer);
      // Кладём nickname и callType прямо в payload offer-а — это позволяет
      // IncomingCallSignalingService на стороне callee сразу показать
      // диалог входящего звонка с правильным именем и типом, не дёргая
      // contacts collection.
      final nickname = await _supabaseService.getNickname();
      final payload = <String, dynamic>{
        ...offer.toMap(),
        'nickname': nickname ?? '',
        'callType': widget.isVideoCall ? 'video' : 'audio',
      };
      await _signaling.sendOffer(
        roomId: widget.chatId,
        targetUserId: target,
        sdp: payload,
      );
      _offerSent = true;
    } catch (error) {
      debugPrint('Offer creation error: $error');
    }
  }

  /// Применяет уже принятый offer (от `IncomingCallSignalingService` через
  /// `widget.initialOffer`) — устанавливает remote description, создаёт
  /// answer и отправляет его caller'у.
  Future<void> _applyRemoteOffer(RTCSessionDescription offer) async {
    final connection = _peerConnection;
    final target = _targetUserId;
    if (connection == null || target == null) return;
    try {
      await connection.setRemoteDescription(offer);
      await _flushPendingCandidates();
      final answer = await connection.createAnswer();
      await connection.setLocalDescription(answer);
      await _signaling.sendAnswer(
        roomId: widget.chatId,
        targetUserId: target,
        sdp: answer.toMap(),
      );
      debugPrint('[stealth-call] answer sent');
    } catch (error) {
      debugPrint('[stealth-call] applyRemoteOffer error: $error');
    }
  }

  /// Единая точка входа для всех входящих сигнальных сообщений. Сервер
  /// уже отфильтровал по target=self, поэтому никаких own-echo проверок
  /// делать не нужно.
  Future<void> _onSignalingMessage(RtcMessage message) async {
    if (message.roomId != widget.chatId) return;
    switch (message.type) {
      case RtcMessageType.offer:
        if (widget.isCaller) {
          // Caller не должен получать чужой offer (это его собственный
          // вызов). Если такое случилось — игнорируем.
          debugPrint('[stealth-call] caller received unexpected offer; ignored');
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
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      final sdp = message.payload['sdp'] as String?;
      final type = message.payload['type'] as String?;
      if (sdp == null || type == null) return;
      await connection.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _flushPendingCandidates();
      debugPrint('[stealth-call] remote answer applied');
    } catch (error) {
      debugPrint('[stealth-call] Answer handling error: $error');
    }
  }

  Future<void> _handleRemoteCandidate(RtcMessage message) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      final payload = message.payload;
      final candidate = RTCIceCandidate(
        payload['candidate'] as String?,
        payload['sdpMid'] as String?,
        payload['sdpMLineIndex'] as int?,
      );
      if (await connection.getRemoteDescription() != null) {
        await connection.addCandidate(candidate);
      } else {
        _pendingRemoteCandidates.add(candidate);
      }
    } catch (error) {
      debugPrint('[stealth-call] Remote candidate error: $error');
    }
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
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _flushPendingCandidates() async {
    final connection = _peerConnection;
    if (connection == null) return;
    for (final candidate in _pendingRemoteCandidates) {
      await connection.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> _attachRemoteStream(MediaStream stream, {MediaStreamTrack? addedTrack}) async {
    _remoteStream = stream;
    if (addedTrack != null && addedTrack.kind == 'audio') {
      addedTrack.enabled = true;
    }
    final audioTracks = stream.getAudioTracks();
    final videoTracks = stream.getVideoTracks();
    for (final track in audioTracks) {
      track.enabled = true;
    }
    // ignore: avoid_print
    print(
      '[stealth-call] remote stream attached: audioTracks=${audioTracks.length} '
      'ids=${audioTracks.map((t) => t.id).toList()}',
    );
    if (videoTracks.isNotEmpty) {
      _remoteRenderer.srcObject = stream;
    }
    // Ремот-трек получен — ещё раз применяем маршрутизацию, чтобы реально
    // услышать собеседника: по умолчанию flutter_webrtc отправляет аудио в
    // earpiece. А реальный статус `connected` ждём от iceConnectionState —
    // иначе UI покажет фейковое подключение до того, как ICE соберётся.
    await _applyAudioRouting();
  }

  void _markConnected() {
    if (!mounted) return;
    if (!_connected) {
      _startTimer();
      _startStatsLogger();
      // Принудительно применяем аудио-роутинг при первом коннекте.
      // Без этого Android оставляет вывод в earpiece (а на эмуляторе
      // earpiece часто не озвучен), и собеседника не слышно даже когда
      // RTP-пакеты идут.
      // ignore: discarded_futures
      _applyAudioRouting();
    }
    _connectionTimeout?.cancel();
    setState(() {
      _connected = true;
      _initializing = false;
    });
  }

  /// Периодически логируем аудио-статистику peer connection, чтобы понимать
  /// идут ли RTP-пакеты и где именно пропадает звук. Вывод видно в logcat под
  /// тегом `flutter`.
  void _startStatsLogger() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final connection = _peerConnection;
      if (connection == null) return;
      try {
        final reports = await connection.getStats();
        for (final report in reports) {
          final type = report.type;
          if (type != 'outbound-rtp' &&
              type != 'inbound-rtp' &&
              type != 'media-source' &&
              type != 'track') {
            continue;
          }
          final kind = report.values['kind'] ?? report.values['mediaType'];
          if (kind != null && kind != 'audio') continue;
          debugPrint(
            '[rtc-stats] $type id=${report.id} '
            'bytesSent=${report.values['bytesSent']} '
            'bytesReceived=${report.values['bytesReceived']} '
            'packetsSent=${report.values['packetsSent']} '
            'packetsReceived=${report.values['packetsReceived']} '
            'audioLevel=${report.values['audioLevel']} '
            'totalAudioEnergy=${report.values['totalAudioEnergy']} '
            'totalSamplesDuration=${report.values['totalSamplesDuration']}',
          );
        }
      } catch (error) {
        debugPrint('[rtc-stats] error: $error');
      }
    });
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callDurationSeconds++);
    });
  }

  void _toggleMicrophone() {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !track.enabled;
    }
    setState(() => _microphoneEnabled = !_microphoneEnabled);
  }

  void _toggleCamera() {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = !track.enabled;
    }
    setState(() => _cameraEnabled = !_cameraEnabled);
  }

  Future<void> _switchCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerEnabled;
    setState(() => _speakerEnabled = next);
    await _applyAudioRouting();
  }

  /// Принудительно маршрутизирует аудио на громкий динамик / earpiece в
  /// соответствии с `_speakerEnabled`. Без этого при audio-only звонке
  /// flutter_webrtc оставляет вывод в earpiece, из-за чего собеседника может
  /// быть не слышно (особенно на эмуляторе, где earpiece не озвучен).
  Future<void> _applyAudioRouting() async {
    if (kIsWeb) return;
    try {
      await Helper.setSpeakerphoneOn(_speakerEnabled);
      // ignore: avoid_print
      print('[stealth-call] speakerphone=$_speakerEnabled');
    } catch (error) {
      // ignore: avoid_print
      print('[stealth-call] setSpeakerphoneOn error: $error');
    }
  }

  Future<void> _hangUp() async {
    // ignore: avoid_print
    print(
      '[stealth-call] _hangUp() isCaller=${widget.isCaller} '
      'connected=$_connected closing=$_closing '
      'stack=${StackTrace.current.toString().split("\n").take(6).join(" | ")}',
    );
    if (_closing) return;
    _closing = true;
    final target = _targetUserId;
    if (target != null) {
      try {
        await _signaling.sendHangup(
          roomId: widget.chatId,
          targetUserId: target,
        );
      } catch (error) {
        debugPrint('[stealth-call] sendHangup error: $error');
      }
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _disposeMedia() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _remoteStream?.getTracks().forEach((track) => track.stop());
    _remoteStream?.dispose();
    _peerConnection?.close();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
        // ignore: avoid_print
        print(
          '[stealth-call] PopScope didPop=$didPop isCaller=${widget.isCaller} '
          'connected=$_connected closing=$_closing',
        );
        if (!didPop) await _hangUp();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: StealthAnimatedBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                        onPressed: _hangUp,
                      ),
                      const Spacer(),
                      const Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'End-to-End Encrypted',
                        style: AppTypography.caption1.copyWith(color: AppColors.textSecondary),
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
                                _remoteStream!.getVideoTracks().isNotEmpty)
                              RTCVideoView(
                                _remoteRenderer,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                              )
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
                                            _localStream!.getVideoTracks().isNotEmpty)
                                        ? RTCVideoView(
                                            _localRenderer,
                                            mirror: true,
                                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                          )
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
                        widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  widget.peerName,
                  style: AppTypography.largeTitle.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  label: AccessibilityIds.callStatus,
                  liveRegion: true,
                  child: Text(
                    _connected ? _formatDuration(_callDurationSeconds) : _initializing ? 'Connecting...' : 'Calling...',
                    style: AppTypography.body.copyWith(
                      color: _connected ? Colors.white : AppColors.textSecondary,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    _buildStatusChip(label: _connected ? 'Connected' : 'Negotiating', active: _connected),
                    _buildStatusChip(label: _microphoneEnabled ? 'Mic on' : 'Mic muted', active: _microphoneEnabled),
                    _buildStatusChip(label: _speakerEnabled ? 'Speaker on' : 'Speaker off', active: _speakerEnabled),
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
                          color: _cameraEnabled ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                          iconColor: _cameraEnabled ? Colors.white : Colors.black,
                          onPressed: _toggleCamera,
                        ),
                      Semantics(
                        label: AccessibilityIds.mute,
                        button: true,
                        child: _buildControlButton(
                          icon: _microphoneEnabled ? Icons.mic : Icons.mic_off,
                          color: _microphoneEnabled ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                          iconColor: _microphoneEnabled ? Colors.white : Colors.black,
                          onPressed: _toggleMicrophone,
                        ),
                      ),
                      Semantics(
                        label: AccessibilityIds.hangUp,
                        button: true,
                        child: _buildControlButton(
                          icon: Icons.call_end,
                          color: AppColors.systemRed,
                          iconColor: Colors.white,
                          size: 72,
                          onPressed: _hangUp,
                        ),
                      ),
                      Semantics(
                        label: AccessibilityIds.speaker,
                        button: true,
                        child: _buildControlButton(
                          icon: _speakerEnabled ? Icons.volume_up : Icons.volume_off,
                          color: _speakerEnabled ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                          iconColor: _speakerEnabled ? Colors.white : Colors.black,
                          onPressed: _toggleSpeaker,
                        ),
                      ),
                      if (widget.isVideoCall)
                        _buildControlButton(
                          icon: Icons.flip_camera_ios_outlined,
                          color: Colors.white.withValues(alpha: 0.2),
                          iconColor: Colors.white,
                          onPressed: _switchCamera,
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: size * 0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({required String label, required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: active ? AppColors.systemGreen.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.08),
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
