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
  return const WebRTCSupport(
    isSupported: false,
    summary: 'WebRTC support is unavailable on this platform.',
    blockingIssues: ['Platform support is missing.'],
    isSecureContext: false,
    hasMediaDevices: false,
    hasPeerConnection: false,
    audioInputCount: 0,
    platformLabel: 'Unsupported platform',
  );
}

Future<String?> requestWebRTCAudioPreflight({bool requireVideo = false}) async {
  return 'Audio preflight is unavailable on this platform.';
}
