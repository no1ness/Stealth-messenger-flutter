import 'dart:js_interop';

import 'package:web/web.dart' as web;

class WebRTCSupport {
  const WebRTCSupport({
    required this.isSupported,
    required this.summary,
    required this.blockingIssues,
    required this.isSecureContext,
    required this.hasMediaDevices,
    required this.hasPeerConnection,
    required this.audioInputCount,
    required this.platformLabel,
  });

  final bool isSupported;
  final String summary;
  final List<String> blockingIssues;
  final bool isSecureContext;
  final bool hasMediaDevices;
  final bool hasPeerConnection;
  final int audioInputCount;
  final String platformLabel;
}

Future<WebRTCSupport> getWebRTCSupport() async {
  final issues = <String>[];
  final isSecureContext = web.window.isSecureContext;

  if (!isSecureContext) {
    issues.add('Open the app over HTTPS or localhost.');
  }

  final mediaDevices = web.window.navigator.mediaDevices;
  final hasMediaDevices = mediaDevices.toString().isNotEmpty;
  if (!hasMediaDevices) {
    issues.add('MediaDevices API is not available in this browser.');
  }

  var hasPeerConnection = true;
  try {
    web.RTCPeerConnection(
      web.RTCConfiguration(
        iceServers: <web.RTCIceServer>[
          web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
        ].toJS,
      ),
    ).close();
  } catch (_) {
    hasPeerConnection = false;
    issues.add('RTCPeerConnection is not available in this browser.');
  }

  var audioInputCount = 0;
  if (hasMediaDevices) {
    try {
      final devices = await mediaDevices.enumerateDevices().toDart;
      audioInputCount = devices
          .toDart
          .where((device) => device.kind == 'audioinput')
          .length;
      if (audioInputCount == 0) {
        issues.add('No audio input device is visible to the browser.');
      }
    } catch (_) {
      issues.add('Unable to enumerate media devices in this browser.');
    }
  }

  if (issues.isEmpty) {
    return WebRTCSupport(
      isSupported: true,
      summary: 'Browser WebRTC is available.',
      blockingIssues: <String>[],
      isSecureContext: isSecureContext,
      hasMediaDevices: hasMediaDevices,
      hasPeerConnection: hasPeerConnection,
      audioInputCount: audioInputCount,
      platformLabel: web.window.navigator.userAgent,
    );
  }

  return WebRTCSupport(
    isSupported: false,
    summary: 'Browser WebRTC is blocked by environment checks.',
    blockingIssues: issues,
    isSecureContext: isSecureContext,
    hasMediaDevices: hasMediaDevices,
    hasPeerConnection: hasPeerConnection,
    audioInputCount: audioInputCount,
    platformLabel: web.window.navigator.userAgent,
  );
}

Future<String?> requestWebRTCAudioPreflight() async {
  final support = await getWebRTCSupport();
  if (!support.isSupported) {
    return support.blockingIssues.join(' ');
  }

  web.MediaStream? stream;
  try {
    stream = await web.window.navigator.mediaDevices
        .getUserMedia(
          web.MediaStreamConstraints(
            audio: true.toJS,
            video: false.toJS,
          ),
        )
        .toDart;
    return null;
  } catch (error) {
    return 'Microphone access failed: $error';
  } finally {
    for (final track in stream?.getTracks().toDart ?? const []) {
      track.stop();
    }
  }
}
