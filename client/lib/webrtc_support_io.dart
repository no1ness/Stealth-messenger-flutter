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
    isSupported: true,
    summary: 'Native WebRTC is available.',
    blockingIssues: <String>[],
    isSecureContext: true,
    hasMediaDevices: true,
    hasPeerConnection: true,
    audioInputCount: 1,
    platformLabel: 'Native platform',
  );
}

Future<String?> requestWebRTCAudioPreflight() async {
  return null;
}
