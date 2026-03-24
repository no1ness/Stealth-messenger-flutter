import 'dart:async';
import 'dart:js_interop';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
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
  final List<web.RTCIceCandidateInit> _pendingRemoteCandidates =
      <web.RTCIceCandidateInit>[];

  web.RTCPeerConnection? _peerConnection;
  web.MediaStream? _localStream;
  web.MediaStream? _remoteStream;
  web.HTMLAudioElement? _remoteAudioElement;
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
  String _signalingState = 'stable';
  String _iceConnectionState = 'new';
  String _connectionState = 'new';
  String? _setupError;

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  @override
  void dispose() {
    _connectionTimeout?.cancel();
    _callTimer?.cancel();
    _disposeMedia();
    _supabaseService.unsubscribeCalls();
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
    _disposeMedia();
    await _supabaseService.unsubscribeCalls();
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

  Future<void> _createPeerConnection() async {
    final configuration = web.RTCConfiguration(
      iceServers: <web.RTCIceServer>[
        web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
      ].toJS,
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
      _supabaseService.sendIceCandidate(
        chatId: widget.chatId,
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    }).toJS;

    peerConnection.ontrack = ((web.Event event) {
      final trackEvent = event as web.RTCTrackEvent;
      if (trackEvent.track.kind != 'audio') {
        return;
      }

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
      if (mounted) {
        setState(() => _iceConnectionState = state);
      }
      if (state == 'connected' || state == 'completed') {
        _markConnected();
      } else if (state == 'failed') {
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
      if (mounted) {
        setState(() => _connectionState = peerConnection.connectionState);
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
            video: false.toJS,
          ),
        )
        .toDart;
    _localStream = stream;
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
  }

  Future<void> _createOffer() async {
    final connection = _peerConnection;
    if (connection == null || _offerSent) {
      return;
    }

    try {
      final offer = await connection
          .createOffer(
            web.RTCOfferOptions(
              offerToReceiveAudio: true,
              offerToReceiveVideo: false,
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
      await _supabaseService.sendOffer(
        chatId: widget.chatId,
        offer: {
          'type': offer.type,
          'sdp': offer.sdp,
        },
      );
      _offerSent = true;
    } catch (error) {
      debugPrint('Offer creation error: $error');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }

    try {
      final offerMap = payload['offer'] ?? payload['sdp'];
      if (offerMap is! Map<String, dynamic>) {
        return;
      }
      final sdp = offerMap['sdp'] as String?;
      final type = offerMap['type'] as String?;
      if (sdp == null || type == null) {
        return;
      }

      await connection
          .setRemoteDescription(
            web.RTCSessionDescriptionInit(type: type, sdp: sdp),
          )
          .toDart;
      await _flushPendingCandidates();
      final answer = await connection.createAnswer().toDart;
      if (answer == null) {
        return;
      }
      await connection
          .setLocalDescription(
            web.RTCLocalSessionDescriptionInit(
              type: answer.type,
              sdp: answer.sdp,
            ),
          )
          .toDart;
      await _supabaseService.sendAnswer(
        chatId: widget.chatId,
        answer: {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      );
    } catch (error) {
      debugPrint('Offer handling error: $error');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }

    try {
      final answerMap = payload['answer'] ?? payload['sdp'];
      if (answerMap is! Map<String, dynamic>) {
        return;
      }
      final sdp = answerMap['sdp'] as String?;
      final type = answerMap['type'] as String?;
      if (sdp == null || type == null) {
        return;
      }

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

  Future<void> _handleRemoteCandidate(Map<String, dynamic> payload) async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }

    try {
      final candidateMap = payload['candidate'];
      if (candidateMap is! Map<String, dynamic>) {
        return;
      }

      final candidate = web.RTCIceCandidateInit(
        candidate: candidateMap['candidate'] as String,
        sdpMid: candidateMap['sdpMid'] as String?,
        sdpMLineIndex: candidateMap['sdpMLineIndex'] as int?,
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
      // Browsers may delay autoplay until the first user gesture; the call UI
      // itself is already the active gesture path, so retry is not required.
    }
    _markConnected();
  }

  void _markConnected() {
    if (!mounted) {
      return;
    }
    if (!_connected) {
      _startTimer();
    }
    _connectionTimeout?.cancel();
    setState(() {
      _connected = true;
      _initializing = false;
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
    final audioElement = _remoteAudioElement;
    if (audioElement != null) {
      audioElement.muted = _speakerEnabled;
    }
    setState(() => _speakerEnabled = !_speakerEnabled);
  }

  Future<void> _hangUp() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _disposeMedia();
    await _supabaseService.sendCallEnd(chatId: widget.chatId);
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
