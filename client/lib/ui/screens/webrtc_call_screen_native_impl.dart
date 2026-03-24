import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';

class WebRTCCallScreen extends StatefulWidget {
  final String peerName;
  final String chatId;
  final bool isCaller;

  const WebRTCCallScreen({
    super.key,
    required this.peerName,
    required this.chatId,
    required this.isCaller,
  });

  @override
  State<WebRTCCallScreen> createState() => _WebRTCCallScreenState();
}

class _WebRTCCallScreenState extends State<WebRTCCallScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  Timer? _connectionTimeout;
  Timer? _callTimer;

  bool _microphoneEnabled = true;
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
    _connectionTimeout?.cancel();
    _callTimer?.cancel();
    _remoteRenderer.dispose();
    _disposeMedia();
    _supabaseService.unsubscribeCalls();
    super.dispose();
  }

  Future<void> _startCall() async {
    if (_startRequested) return;
    _startRequested = true;
    try {
      if (!kIsWeb) {
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

      await _createPeerConnection();
      await _createLocalStream();
      await _attachLocalAudio();

      await _supabaseService.subscribeCalls(
        chatId: widget.chatId,
        onOfferReceived: _handleOffer,
        onAnswerReceived: _handleAnswer,
        onIceCandidateReceived: _handleRemoteCandidate,
      );

      _connectionTimeout = Timer(const Duration(seconds: 30), () {
        if (!_connected && mounted) {
          _showSnackBar('Connection timed out.');
          _hangUp();
        }
      });

      if (widget.isCaller) {
        await _createOffer();
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

  Future<bool> _requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) return true;
      if (!mounted) return false;
      _showSnackBar('Enable microphone access in settings.');
      return false;
    } catch (error) {
      debugPrint('Permission request error: $error');
      return true;
    }
  }

  Future<void> _createPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
        },
      ],
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 4,
    };

    _peerConnection = await createPeerConnection(configuration, {
      'mandatory': <String, dynamic>{},
      'optional': <dynamic>[],
    });

    _peerConnection!.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      _supabaseService.sendIceCandidate(
        chatId: widget.chatId,
        candidate: candidate.toMap(),
      );
    };

    _peerConnection!.onTrack = (event) async {
      if (event.track.kind != 'audio') return;
      if (event.streams.isNotEmpty) {
        await _attachRemoteStream(event.streams.first, addedTrack: event.track);
        return;
      }
      final fallback = _remoteStream ?? await createLocalMediaStream('remote');
      if (!fallback.getTracks().any((track) => track.id == event.track.id)) {
        fallback.addTrack(event.track);
      }
      await _attachRemoteStream(fallback, addedTrack: event.track);
    };

    _peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _showSnackBar('Connection failed.');
        _hangUp();
      }
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
        'video': false,
      });
    } catch (_) {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    }
  }

  Future<void> _attachLocalAudio() async {
    final connection = _peerConnection;
    final stream = _localStream;
    if (connection == null || stream == null) return;
    final audioTracks = stream.getAudioTracks();
    if (audioTracks.isEmpty) throw Exception('No microphone track available.');
    final audioTrack = audioTracks.first;
    if (kIsWeb) {
      await connection.addTransceiver(
        track: audioTrack,
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendRecv,
          streams: [stream],
        ),
      );
      return;
    }
    await connection.addTrack(audioTrack, stream);
  }

  Future<void> _createOffer() async {
    final connection = _peerConnection;
    if (connection == null || _offerSent) return;
    try {
      final offer = await connection.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await connection.setLocalDescription(offer);
      await _supabaseService.sendOffer(chatId: widget.chatId, offer: offer.toMap());
      _offerSent = true;
    } catch (error) {
      debugPrint('Offer creation error: $error');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      final offerMap = payload['offer'] ?? payload['sdp'];
      if (offerMap is! Map<String, dynamic>) return;
      final sdp = offerMap['sdp'] as String?;
      final type = offerMap['type'] as String?;
      if (sdp == null || type == null) return;
      await connection.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _flushPendingCandidates();
      final answer = await connection.createAnswer();
      await connection.setLocalDescription(answer);
      await _supabaseService.sendAnswer(chatId: widget.chatId, answer: answer.toMap());
    } catch (error) {
      debugPrint('Offer handling error: $error');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      final answerMap = payload['answer'] ?? payload['sdp'];
      if (answerMap is! Map<String, dynamic>) return;
      final sdp = answerMap['sdp'] as String?;
      final type = answerMap['type'] as String?;
      if (sdp == null || type == null) return;
      await connection.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _flushPendingCandidates();
    } catch (error) {
      debugPrint('Answer handling error: $error');
    }
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> payload) async {
    final connection = _peerConnection;
    if (connection == null) return;
    try {
      final candidateMap = payload['candidate'];
      if (candidateMap is! Map<String, dynamic>) return;
      final candidate = RTCIceCandidate(
        candidateMap['candidate'] as String?,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      );
      if (await connection.getRemoteDescription() != null) {
        await connection.addCandidate(candidate);
      } else {
        _pendingRemoteCandidates.add(candidate);
      }
    } catch (error) {
      debugPrint('Remote candidate error: $error');
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
    for (final track in stream.getAudioTracks()) {
      track.enabled = true;
    }
    if (stream.getVideoTracks().isNotEmpty) {
      _remoteRenderer.srcObject = stream;
    }
    _markConnected();
  }

  void _markConnected() {
    if (!mounted) return;
    if (!_connected) _startTimer();
    _connectionTimeout?.cancel();
    setState(() {
      _connected = true;
      _initializing = false;
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

  void _toggleSpeaker() {
    setState(() => _speakerEnabled = !_speakerEnabled);
  }

  Future<void> _hangUp() async {
    if (_closing) return;
    _closing = true;
    await _supabaseService.sendCallEnd(chatId: widget.chatId);
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
                Text(
                  _connected ? _formatDuration(_callDurationSeconds) : _initializing ? 'Connecting...' : 'Calling...',
                  style: AppTypography.body.copyWith(
                    color: _connected ? Colors.white : AppColors.textSecondary,
                    fontFeatures: [const FontFeature.tabularFigures()],
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
                      _buildControlButton(
                        icon: _microphoneEnabled ? Icons.mic : Icons.mic_off,
                        color: _microphoneEnabled ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                        iconColor: _microphoneEnabled ? Colors.white : Colors.black,
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
                        icon: _speakerEnabled ? Icons.volume_up : Icons.volume_off,
                        color: _speakerEnabled ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                        iconColor: _speakerEnabled ? Colors.white : Colors.black,
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
