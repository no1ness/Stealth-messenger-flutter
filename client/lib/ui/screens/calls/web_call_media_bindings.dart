import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stealth/logging/logger.dart';
import 'package:web/web.dart' as web;

/// Web (browser) WebRTC media plumbing for the web variant of
/// `WebRTCCallScreen`.
///
/// Mirrors `NativeCallMediaBindings`, но базируется на `package:web` (DOM
/// API), а не на `flutter_webrtc`. Браузерный API диктует:
/// - использовать `HTMLVideoElement` для рендера через `HtmlElementView`;
/// - управлять аудио через `HTMLAudioElement.muted`, а не Helper;
/// - вместо `getStats()` в native — поллинг audio-track readyState;
/// - регистрировать platform-view types через `ui_web.platformViewRegistry`.
class WebCallMediaBindings {
  WebCallMediaBindings();

  static final Set<String> _registeredViewTypes = <String>{};

  final List<web.RTCIceCandidateInit> _pendingRemoteCandidates =
      <web.RTCIceCandidateInit>[];

  web.RTCPeerConnection? _peerConnection;
  web.MediaStream? _localStream;
  web.MediaStream? _remoteStream;
  web.HTMLAudioElement? _remoteAudioElement;
  web.HTMLVideoElement? _remoteVideoElement;
  web.HTMLVideoElement? _localVideoElement;
  Timer? _audioAuditTimer;

  bool _speakerphoneOn = true;
  bool _offerSent = false;

  web.MediaStream? get localStream => _localStream;
  web.MediaStream? get remoteStream => _remoteStream;

  bool get hasLocalVideo =>
      _localStream != null && _localStream!.getVideoTracks().toDart.isNotEmpty;
  bool get hasRemoteVideo =>
      _remoteStream != null &&
      _remoteStream!.getVideoTracks().toDart.isNotEmpty;

  void initVideoElements({
    required String remoteViewType,
    required String localViewType,
  }) {
    _remoteVideoElement = web.HTMLVideoElement()
      ..autoplay = true
      ..playsInline = true
      ..muted = !_speakerphoneOn
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
    _registerViewType(remoteViewType, (_) => _remoteVideoElement!);
    _registerViewType(localViewType, (_) => _localVideoElement!);
  }

  void _registerViewType(
      String viewType, web.HTMLElement Function(int) factory) {
    if (_registeredViewTypes.contains(viewType)) return;
    ui_web.platformViewRegistry.registerViewFactory(viewType, factory);
    _registeredViewTypes.add(viewType);
  }

  Future<void> createPeerConnection({
    required void Function(Map<String, dynamic> candidate) onLocalCandidate,
    required Future<void> Function(bool isVideoCall) onRemoteStreamReady,
    required void Function(String state) onIceConnectionState,
    required void Function(String state) onSignalingState,
    required void Function(String state) onConnectionState,
    required bool isVideoCall,
  }) async {
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
      Logger.warn(
          '[stealth-call] web: no TURN/TURNS in .env — P2P may fail across NAT');
    }

    final pc = web.RTCPeerConnection(
      web.RTCConfiguration(
        iceServers: iceServers.toJS,
        iceCandidatePoolSize: 4,
      ),
    );
    _peerConnection = pc;

    pc.onicecandidate = ((web.Event event) {
      final iceEvent = event as web.RTCPeerConnectionIceEvent;
      final candidate = iceEvent.candidate;
      if (candidate == null || candidate.candidate.isEmpty) return;
      onLocalCandidate({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    }).toJS;

    pc.ontrack = ((web.Event event) {
      final trackEvent = event as web.RTCTrackEvent;
      final streams = trackEvent.streams.toDart;
      if (streams.isNotEmpty) {
        // ignore: discarded_futures
        _attachRemoteStream(streams.first, isVideoCall: isVideoCall)
            .then((_) => onRemoteStreamReady(isVideoCall));
        return;
      }
      final fallback = _remoteStream ?? web.MediaStream();
      fallback.addTrack(trackEvent.track);
      // ignore: discarded_futures
      _attachRemoteStream(fallback, isVideoCall: isVideoCall)
          .then((_) => onRemoteStreamReady(isVideoCall));
    }).toJS;

    pc.oniceconnectionstatechange = ((web.Event event) {
      final state = pc.iceConnectionState;
      Logger.info('[stealth-call] web iceState', extras: {'state': state});
      onIceConnectionState(state);
    }).toJS;

    pc.onsignalingstatechange = ((web.Event event) {
      onSignalingState(pc.signalingState);
    }).toJS;

    pc.onconnectionstatechange = ((web.Event event) {
      final state = pc.connectionState;
      Logger.info('[stealth-call] web peerState', extras: {'state': state});
      onConnectionState(state);
    }).toJS;
  }

  Future<void> createLocalStream({required bool isVideoCall}) async {
    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(
          web.MediaStreamConstraints(
            audio: {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            }.jsify() as JSAny,
            video: isVideoCall
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
    if (isVideoCall && _localVideoElement != null) {
      _localVideoElement!.srcObject = stream;
      // ignore: discarded_futures
      _playLocalPreview();
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

  Future<void> attachLocalAudio({required bool isVideoCall}) async {
    final connection = _peerConnection;
    final stream = _localStream;
    if (connection == null || stream == null) return;

    final audioTracks = stream.getAudioTracks().toDart;
    if (audioTracks.isEmpty) {
      throw Exception('No microphone track available.');
    }
    for (final track in audioTracks) {
      connection.addTrack(track, stream);
    }
    if (isVideoCall) {
      final videoTracks = stream.getVideoTracks().toDart;
      for (final track in videoTracks) {
        connection.addTrack(track, stream);
      }
    }
  }

  Future<Map<String, dynamic>?> createLocalOffer({
    required bool isVideoCall,
  }) async {
    final connection = _peerConnection;
    if (connection == null || _offerSent) return null;
    try {
      final offer = await connection
          .createOffer(
            web.RTCOfferOptions(
              offerToReceiveAudio: true,
              offerToReceiveVideo: isVideoCall,
            ),
          )
          .toDart;
      if (offer == null) return null;
      await connection
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(
              type: offer.type,
              sdp: offer.sdp,
            ),
          )
          .toDart;
      _offerSent = true;
      return {'type': offer.type, 'sdp': offer.sdp};
    } catch (error) {
      Logger.warn('[stealth-call] web offer creation error',
          extras: {'error': error});
      return null;
    }
  }

  Future<Map<String, dynamic>?> applyRemoteOffer(
      Map<String, dynamic> offerMap) async {
    final connection = _peerConnection;
    final sdp = offerMap['sdp'] as String?;
    final type = offerMap['type'] as String?;
    if (connection == null || sdp == null || type == null) return null;
    try {
      await connection
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(type: type, sdp: sdp),
          )
          .toDart;
      await flushPendingCandidates();
      final answer = await connection.createAnswer().toDart;
      if (answer == null) return null;
      await connection
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(
              type: answer.type,
              sdp: answer.sdp,
            ),
          )
          .toDart;
      return {'type': answer.type, 'sdp': answer.sdp};
    } catch (error) {
      Logger.warn('[stealth-call] web applyRemoteOffer error',
          extras: {'error': error});
      return null;
    }
  }

  Future<void> applyRemoteAnswer(
      {required String type, required String sdp}) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      await connection
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(type: type, sdp: sdp),
          )
          .toDart;
      await flushPendingCandidates();
    } catch (error) {
      Logger.warn('[stealth-call] web answer handling error',
          extras: {'error': error});
    }
  }

  Future<void> addOrBufferRemoteCandidate(Map<String, dynamic> payload) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
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
      Logger.warn('[stealth-call] web remote candidate error',
          extras: {'error': error});
    }
  }

  Future<void> flushPendingCandidates() async {
    final connection = _peerConnection;
    if (connection == null) return;
    for (final candidate in _pendingRemoteCandidates) {
      await connection.addIceCandidate(candidate).toDart;
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> _attachRemoteStream(
    web.MediaStream stream, {
    required bool isVideoCall,
  }) async {
    _remoteStream = stream;
    if (isVideoCall && _remoteVideoElement != null) {
      _remoteVideoElement!
        ..muted = !_speakerphoneOn
        ..srcObject = stream;
      try {
        await _remoteVideoElement!.play().toDart;
      } catch (_) {
        // ignore autoplay-related errors, browser may require user gesture.
      }
    } else {
      _remoteAudioElement ??= web.HTMLAudioElement()
        ..autoplay = true
        ..muted = !_speakerphoneOn;
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
    Logger.info('[stealth-call] web remote stream attached', extras: {
      'audio': stream.getAudioTracks().toDart.length,
      'video': stream.getVideoTracks().toDart.length,
    });
  }

  void setMicrophoneEnabled(bool enabled) {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks().toDart) {
      track.enabled = enabled;
    }
  }

  void setCameraEnabled(bool enabled) {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks().toDart) {
      track.enabled = enabled;
    }
  }

  /// Web: speakerphone маршрутизация делается через `.muted` на DOM-элементе.
  void setSpeakerphoneOn(bool enabled) {
    _speakerphoneOn = enabled;
    final videoElement = _remoteVideoElement;
    if (videoElement != null) {
      videoElement.muted = !enabled;
    }
    final audioElement = _remoteAudioElement;
    if (audioElement != null) {
      audioElement.muted = !enabled;
    }
  }

  /// Периодически проверяем состояние аудио-треков. Вывод видно в DevTools.
  void startAudioAudit() {
    _audioAuditTimer?.cancel();
    _audioAuditTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final remote = _remoteStream;
      if (remote == null) return;
      for (final track in remote.getAudioTracks().toDart) {
        Logger.debug('[stealth-audio-audit] remote audio track', extras: {
          'id': track.id,
          'kind': track.kind,
          'readyState': track.readyState,
          'enabled': track.enabled,
          'muted': track.muted,
          'label': track.label,
        });
      }
      final local = _localStream;
      if (local == null) return;
      for (final track in local.getAudioTracks().toDart) {
        Logger.debug('[stealth-audio-audit] local audio track', extras: {
          'id': track.id,
          'readyState': track.readyState,
          'enabled': track.enabled,
          'muted': track.muted,
          'label': track.label,
        });
      }
    });
  }

  Future<void> dispose() async {
    _audioAuditTimer?.cancel();
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

  /// Полный reset перед `retry` — освобождает media и сбрасывает offer-флаг,
  /// чтобы повторный `createLocalOffer` отправил новый offer.
  void resetForRetry() {
    _offerSent = false;
    _pendingRemoteCandidates.clear();
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
    Logger.info('[stealth-call] web ice server configured',
        extras: {'label': label, 'urls': raw});
  }
}
