import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/webrtc/ice_config.dart';

/// Native (mobile/desktop) WebRTC media plumbing for [WebRTCCallScreen].
///
/// Plain class — no [ChangeNotifier]. Owns the peer connection, local/remote
/// streams, video renderers, the stats timer, and the pending remote
/// candidates buffer. Signaling and UI state live in `NativeCallController`,
/// which wires media events back via the callbacks passed to
/// [createPeerConnection].
class NativeCallMediaBindings {
  NativeCallMediaBindings();

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  Timer? _statsTimer;

  bool _speakerphoneOn = true;
  bool _offerSent = false;

  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  bool get hasLocalVideo =>
      _localStream != null && _localStream!.getVideoTracks().isNotEmpty;
  bool get hasRemoteVideo =>
      _remoteStream != null && _remoteStream!.getVideoTracks().isNotEmpty;

  Future<void> initializeRenderers() async {
    if (kIsWeb) return;
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  /// Returns `null` when all needed permissions are granted, otherwise the
  /// error message the caller can surface to the user.
  Future<String?> requestPermissions({required bool isVideoCall}) async {
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        return 'Enable microphone access in settings.';
      }
      if (isVideoCall) {
        final cam = await Permission.camera.request();
        if (!cam.isGranted) {
          return 'Enable camera access in settings.';
        }
      }
      return null;
    } catch (error) {
      Logger.warn('[stealth-call] permission request error',
          extras: {'error': error});
      return null;
    }
  }

  Future<void> createPeerConnection({
    required void Function(RTCIceCandidate candidate) onLocalCandidate,
    required Future<void> Function() onRemoteStreamReady,
    required void Function(RTCIceConnectionState state) onIceConnectionState,
  }) async {
    final configuration = <String, dynamic>{
      'iceServers': buildIceServers(),
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 4,
      'iceTransportPolicy': 'all',
    };

    final pc = await createPeerConnectionFactory(configuration);
    _peerConnection = pc;

    pc.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      onLocalCandidate(candidate);
    };

    pc.onTrack = (event) async {
      Logger.info('[stealth-call] onTrack', extras: {
        'kind': event.track.kind,
        'id': event.track.id,
        'enabled': event.track.enabled,
        'streams': event.streams.length,
      });
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        for (final track in stream.getTracks()) {
          track.enabled = true;
        }
        await _attachRemoteStream(stream, addedTrack: event.track);
        await onRemoteStreamReady();
        return;
      }
      final fallback = _remoteStream ?? await createLocalMediaStream('remote');
      if (!fallback.getTracks().any((track) => track.id == event.track.id)) {
        fallback.addTrack(event.track);
      }
      event.track.enabled = true;
      await _attachRemoteStream(fallback, addedTrack: event.track);
      await onRemoteStreamReady();
    };

    pc.onIceConnectionState = (state) {
      Logger.info('[stealth-call] iceState',
          extras: {'state': state.toString()});
      onIceConnectionState(state);
    };

    pc.onConnectionState = (state) {
      Logger.info('[stealth-call] peerState',
          extras: {'state': state.toString()});
    };
  }

  Future<void> createLocalStream({required bool isVideoCall}) async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideoCall
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
    } catch (error) {
      Logger.warn('[stealth-call] getUserMedia strict failed, falling back',
          extras: {'error': error});
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideoCall,
      });
    }
    final audioTracks = _localStream?.getAudioTracks() ?? const [];
    Logger.info('[stealth-call] local stream ready', extras: {
      'audio': audioTracks.length,
      'ids': audioTracks.map((t) => t.id).toList(),
      'enabled': audioTracks.map((t) => t.enabled).toList(),
    });
    if (_localStream != null && isVideoCall) {
      _localRenderer.srcObject = _localStream;
    }
  }

  Future<void> attachLocalMedia({required bool isVideoCall}) async {
    final connection = _peerConnection;
    final stream = _localStream;
    if (connection == null || stream == null) return;
    final audioTracks = stream.getAudioTracks();
    if (audioTracks.isEmpty) {
      throw Exception('No microphone track available.');
    }
    for (final track in audioTracks) {
      await connection.addTrack(track, stream);
    }
    if (isVideoCall) {
      for (final track in stream.getVideoTracks()) {
        await connection.addTrack(track, stream);
      }
    }
  }

  /// Создаёт offer, выставляет local description и возвращает payload как
  /// Map для отправки через signaling. Идемпотентен — повторный вызов после
  /// успешного offer не отправит ничего и вернёт `null`.
  Future<Map<String, dynamic>?> createLocalOffer({
    required bool isVideoCall,
  }) async {
    final connection = _peerConnection;
    if (connection == null || _offerSent) return null;
    try {
      final offer = await connection.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': isVideoCall ? 1 : 0,
      });
      await connection.setLocalDescription(offer);
      _offerSent = true;
      return offer.toMap();
    } catch (error) {
      Logger.warn('[stealth-call] offer creation error',
          extras: {'error': error});
      return null;
    }
  }

  /// Применяет принятый offer и возвращает answer payload для отправки.
  Future<Map<String, dynamic>?> applyRemoteOffer(
      RTCSessionDescription offer) async {
    final connection = _peerConnection;
    if (connection == null) return null;
    try {
      await connection.setRemoteDescription(offer);
      await flushPendingCandidates();
      final answer = await connection.createAnswer();
      await connection.setLocalDescription(answer);
      Logger.info('[stealth-call] answer ready');
      return answer.toMap();
    } catch (error) {
      Logger.warn('[stealth-call] applyRemoteOffer error',
          extras: {'error': error});
      return null;
    }
  }

  Future<void> applyRemoteAnswer(RTCSessionDescription answer) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      await connection.setRemoteDescription(answer);
      await flushPendingCandidates();
      Logger.info('[stealth-call] remote answer applied');
    } catch (error) {
      Logger.warn('[stealth-call] answer handling error',
          extras: {'error': error});
    }
  }

  Future<void> addOrBufferRemoteCandidate(RTCIceCandidate candidate) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      if (await connection.getRemoteDescription() != null) {
        await connection.addCandidate(candidate);
      } else {
        _pendingRemoteCandidates.add(candidate);
      }
    } catch (error) {
      Logger.warn('[stealth-call] remote candidate error',
          extras: {'error': error});
    }
  }

  Future<void> flushPendingCandidates() async {
    final connection = _peerConnection;
    if (connection == null) return;
    for (final candidate in _pendingRemoteCandidates) {
      await connection.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> _attachRemoteStream(
    MediaStream stream, {
    MediaStreamTrack? addedTrack,
  }) async {
    _remoteStream = stream;
    if (addedTrack != null && addedTrack.kind == 'audio') {
      addedTrack.enabled = true;
    }
    final audioTracks = stream.getAudioTracks();
    final videoTracks = stream.getVideoTracks();
    for (final track in audioTracks) {
      track.enabled = true;
    }
    Logger.info('[stealth-call] remote stream attached', extras: {
      'audioTracks': audioTracks.length,
      'ids': audioTracks.map((t) => t.id).toList(),
    });
    if (videoTracks.isNotEmpty) {
      _remoteRenderer.srcObject = stream;
    }
    await applyAudioRouting();
  }

  void setMicrophoneEnabled(bool enabled) {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = enabled;
    }
  }

  void setCameraEnabled(bool enabled) {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
  }

  Future<void> setSpeakerphoneOn(bool enabled) async {
    _speakerphoneOn = enabled;
    await applyAudioRouting();
  }

  /// Принудительно маршрутизирует аудио на громкий динамик / earpiece в
  /// соответствии с текущим значением `_speakerphoneOn`. Без этого при
  /// audio-only звонке flutter_webrtc оставляет вывод в earpiece, из-за
  /// чего собеседника может быть не слышно (особенно на эмуляторе, где
  /// earpiece не озвучен).
  Future<void> applyAudioRouting() async {
    if (kIsWeb) return;
    try {
      await Helper.setSpeakerphoneOn(_speakerphoneOn);
      Logger.info('[stealth-call] speakerphone',
          extras: {'enabled': _speakerphoneOn});
    } catch (error) {
      Logger.warn('[stealth-call] setSpeakerphoneOn error',
          extras: {'error': error});
    }
  }

  /// Периодически логируем аудио-статистику peer connection.
  void startStatsLogger() {
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
          Logger.debug('[rtc-stats]', extras: {
            'type': type,
            'id': report.id,
            'bytesSent': report.values['bytesSent'],
            'bytesReceived': report.values['bytesReceived'],
            'packetsSent': report.values['packetsSent'],
            'packetsReceived': report.values['packetsReceived'],
            'audioLevel': report.values['audioLevel'],
            'totalAudioEnergy': report.values['totalAudioEnergy'],
            'totalSamplesDuration': report.values['totalSamplesDuration'],
          });
        }
      } catch (error) {
        Logger.warn('[rtc-stats] error', extras: {'error': error});
      }
    });
  }

  Future<void> dispose() async {
    _statsTimer?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _remoteStream?.getTracks().forEach((track) => track.stop());
    await _remoteStream?.dispose();
    await _peerConnection?.close();
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  // ICE config moved to `services/webrtc/ice_config.dart` (task #8) —
  // both native call media and P2PService delegate there.
}

/// Глобальная функция `createPeerConnection` из `flutter_webrtc` конфликтует
/// с методом в [NativeCallMediaBindings]. Чтобы не использовать prefix-import
/// на всю библиотеку, оборачиваем вызов здесь.
Future<RTCPeerConnection> createPeerConnectionFactory(
    Map<String, dynamic> configuration) {
  return createPeerConnection(configuration, {
    'mandatory': <String, dynamic>{},
    'optional': <dynamic>[],
  });
}
