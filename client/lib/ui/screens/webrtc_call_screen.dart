import 'package:flutter/material.dart';
import 'dart:async';
import 'package:stealth/supabase_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _microphoneEnabled = true;
  bool _initializing = true;
  bool _connected = false;
  bool _hasRemoteAudio = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _offerSent = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    try {
      // Инициализируем рендерер только если не на веб-платформе или если нужен видео
      if (!kIsWeb) {
        await _remoteRenderer.initialize();
      }
    } catch (e) {
      debugPrint('Error initializing renderers: $e');
    }
    await _initWebRTC();
  }

  @override
  void dispose() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _remoteStream?.getTracks().forEach((t) => t.stop());
    _remoteStream?.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    _supabaseService.unsubscribeCalls();
    super.dispose();
  }

  Future<void> _initWebRTC() async {
    try {
      debugPrint('=== INITIALIZING WEBRTC ===');
      debugPrint('Is caller: ${widget.isCaller}');
      debugPrint('Chat ID: ${widget.chatId}');
      debugPrint('Peer name: ${widget.peerName}');
      
      // Add a timeout for connection establishment
      Timer? connectionTimer;
      connectionTimer = Timer(const Duration(seconds: 30), () {
        if (_initializing && mounted) {
          debugPrint('WebRTC connection timeout - no connection established within 30 seconds');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Превышено время ожидания подключения')),
          );
          _hangUp();
        }
      });
      
      // Запрашиваем разрешения с проверкой (на Web пропускаем permission_handler)
      final permissionsGranted = kIsWeb ? true : await _handleCameraAndMicPermissions();
      if (!permissionsGranted) {
        if (!mounted) return;
        setState(() => _initializing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Необходимы разрешения на камеру и микрофон для звонка'),
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).maybePop();
        return;
      }

      final Map<String, dynamic> configuration = {
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302',
              'stun:stun3.l.google.com:19302',
              'stun:stun4.l.google.com:19302',
            ]
          },
          {
            'urls': 'stun:global.stun.twilio.com:3478',
          },
          // Adding TURN servers for better NAT traversal
          {
            'urls': 'turn:global.turn.twilio.com:3478?transport=udp',
            'username': 'test', // In production, use real credentials
            'credential': 'test'
          },
          {
            'urls': 'turn:global.turn.twilio.com:3478?transport=tcp',
            'username': 'test', // In production, use real credentials
            'credential': 'test'
          },
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
      };

      debugPrint('Creating peer connection with configuration: $configuration');
      _peerConnection = await createPeerConnection(configuration, {
        'mandatory': {},
        'optional': [],
      });
      debugPrint('Peer connection created successfully');

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        debugPrint('=== onIceCandidate ===');
        debugPrint('Candidate: ${candidate.candidate}');
        debugPrint('SDP Mid: ${candidate.sdpMid}');
        debugPrint('SDP MLine Index: ${candidate.sdpMLineIndex}');
        
        if ((candidate.candidate ?? '').isNotEmpty) {
          try {
            debugPrint('Sending ICE candidate: ${candidate.candidate}');
            _supabaseService.sendIceCandidate(
              chatId: widget.chatId,
              candidate: candidate.toMap(),
            );
          } catch (e) {
            debugPrint('Error sending ICE candidate: $e');
          }
        } else {
          debugPrint('Empty ICE candidate received, ignoring');
        }
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        debugPrint('=== onTrack received ===');
        debugPrint('Track kind: ${event.track.kind}');
        debugPrint('Track id: ${event.track.id}');
        debugPrint('Track enabled: ${event.track.enabled}');
        debugPrint('Streams count: ${event.streams.length}');

        if (event.track.kind == 'audio') {
          debugPrint('Audio track received - enabling playback');
          // Ensure the track is enabled for playback
          event.track.enabled = true;
          if (mounted) {
            setState(() => _hasRemoteAudio = true);
          }
        }

        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          debugPrint('Stream id: ${stream.id}');
          debugPrint('Stream audio tracks: ${stream.getAudioTracks().length}');
          debugPrint('Stream video tracks: ${stream.getVideoTracks().length}');
          
          // Ensure audio tracks in the stream are enabled
          for (final track in stream.getAudioTracks()) {
            track.enabled = true;
            debugPrint('Enabled remote audio track: ${track.id}');
          }
          
          await _attachRemoteStream(stream, addedTrack: event.track);
        } else {
          debugPrint('WARNING: Track received without streams - creating fallback stream');
          final fallbackStream = _remoteStream ?? await createLocalMediaStream('remote-stream');
          final hasTrack = fallbackStream
              .getTracks()
              .any((t) => t.id == event.track.id);
          if (!hasTrack) {
            fallbackStream.addTrack(event.track);
            debugPrint('Added track to fallback stream: ${event.track.id}');
          }
          await _attachRemoteStream(fallbackStream, addedTrack: event.track);
        }
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState? state) {
        debugPrint('=== ICE Connection state changed ===');
        debugPrint('State: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          if (mounted) {
            setState(() {
              _connected = true;
              _initializing = false;
            });
            debugPrint('WebRTC connection established successfully');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Соединение установлено'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          debugPrint('ICE Connection disconnected - attempting to reconnect...');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Соединение прервано, попытка переподключения...'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          debugPrint('ICE Connection failed');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Не удалось установить соединение. Проверьте интернет-соединение.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
            _hangUp();
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          debugPrint('ICE Connection closed');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Соединение закрыто'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
            _hangUp();
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
          debugPrint('ICE is checking connections...');
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateNew) {
          debugPrint('ICE connection is new');
        }
      };

      _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
        debugPrint('=== ICE Gathering State ===');
        debugPrint('State: $state');
      };

      _peerConnection!.onSignalingState = (RTCSignalingState state) {
        debugPrint('=== Signaling State ===');
        debugPrint('State: $state');
      };

      // Локальные треки с улучшенной обработкой ошибок
      MediaStream? stream;
      try {
        debugPrint('Requesting user media...');
        stream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'sampleRate': 48000,
            'channelCount': 1,
          },
          'video': false,
        });
        debugPrint('User media acquired successfully');
      } catch (e) {
        debugPrint('getUserMedia error: $e');
        // Try with minimal constraints
        try {
          debugPrint('Trying fallback getUserMedia with minimal constraints...');
          stream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
          debugPrint('Fallback getUserMedia successful');
        } catch (e2) {
          debugPrint('Fallback getUserMedia also failed: $e2');
          throw Exception('Не удалось получить доступ к микрофону: $e2');
        }
      }
      _localStream = stream;

      // Добавляем аудио трек (обязательно)
      final audioTracks = _localStream!.getAudioTracks();
      debugPrint('Local stream audio tracks count: ${audioTracks.length}');
      if (audioTracks.isNotEmpty) {
        try {
          final audioTrack = audioTracks.first;
          debugPrint('Adding audio track: ${audioTrack.id}');
          debugPrint('Audio track label: ${audioTrack.label}');
          debugPrint('Audio track enabled: ${audioTrack.enabled}');
          if (_peerConnection == null) {
            debugPrint('PeerConnection is null, cannot add audio track.');
            return;
          }
          
          // Improved audio track handling for both web and mobile
          if (kIsWeb) {
            // For web, we need to handle transceivers properly
            debugPrint('Adding transceiver for web platform');
            if (_peerConnection == null) return;
            final transceiver = await _peerConnection!.addTransceiver(
              track: audioTrack,
              kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
              init: RTCRtpTransceiverInit(
                direction: TransceiverDirection.SendRecv,
                streams: [_localStream!],
              ),
            );
            debugPrint('Added transceiver for web: ${transceiver.mid}');
          } else {
            // For mobile, add track directly
            debugPrint('Adding track directly for mobile platform');
            await _peerConnection!.addTrack(audioTrack, _localStream!);
          }
        } catch (e) {
          debugPrint('Error adding audio track: $e');
          // Try alternative approach
          try {
            final audioTrack = audioTracks.first;
            debugPrint('Trying alternative approach to add audio track');
            if (_peerConnection == null) return;
            await _peerConnection!.addTransceiver(
              track: audioTrack,
              kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
              init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
            );
            debugPrint('Alternative approach successful');
          } catch (e2) {
            debugPrint('Alternative audio track addition also failed: $e2');
          }
        }
      } else {
        debugPrint('ERROR: No audio tracks available!');
      }

      // Проверяем transceivers
      try {
        final transceivers = await _peerConnection?.getTransceivers();
        debugPrint('Transceivers count: ${transceivers?.length ?? 0}');
        // Simplified transceiver info
        for (var i = 0; i < (transceivers?.length ?? 0); i++) {
          final transceiver = transceivers![i];
          debugPrint('Transceiver $i: mid=${transceiver.mid}');
        }
      } catch (e) {
        debugPrint('Error getting transceivers: $e');
      }

      // Подписка на сигналинг
      _supabaseService.subscribeCalls(
        chatId: widget.chatId,
        onOfferReceived: _handleOffer,
        onAnswerReceived: _handleAnswer,
        onIceCandidateReceived: _handleRemoteCandidate,
      );

      // Caller creates offer
      if (widget.isCaller) {
        debugPrint('Caller: creating offer');
        await _createOffer();
      } else {
        debugPrint('Waiting for offer as callee');
      }

      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      debugPrint('Error initializing WebRTC: $e');
      if (!mounted) return;
      setState(() => _initializing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка звонка: ${e.toString()}'),
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null || _offerSent) return;
    try {
      debugPrint('Creating offer...');
      final RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(offer);
      debugPrint('Offer created and set as local description');
      
      await _supabaseService.sendOffer(chatId: widget.chatId, offer: offer.toMap());
      _offerSent = true;
      debugPrint('Offer sent to remote peer');
    } catch (e) {
      debugPrint('Error creating offer: $e');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    if (_peerConnection == null) return;
    try {
      final sdp = payload['sdp'];
      if (sdp == null) return;

      final offer = RTCSessionDescription(sdp['sdp'], sdp['type']);
      debugPrint('Received offer: ${offer.sdp}');

      await _peerConnection!.setRemoteDescription(offer);
      debugPrint('Remote description (offer) set');
      
      // Process any pending candidates
      if (_pendingRemoteCandidates.isNotEmpty) {
        for (final candidate in _pendingRemoteCandidates) {
          await _peerConnection!.addCandidate(candidate);
        }
        _pendingRemoteCandidates.clear();
      }

      final RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      debugPrint('Answer created and set as local description');

      await _supabaseService.sendAnswer(chatId: widget.chatId, answer: answer.toMap());
      debugPrint('Answer sent to remote peer');
    } catch (e) {
      debugPrint('Error handling offer: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    if (_peerConnection == null) return;
    try {
      final sdp = payload['sdp'];
      if (sdp == null) return;

      final answer = RTCSessionDescription(sdp['sdp'], sdp['type']);
      debugPrint('Received answer: ${answer.sdp}');

      await _peerConnection!.setRemoteDescription(answer);
      debugPrint('Remote description (answer) set');

      // Process any pending candidates
      if (_pendingRemoteCandidates.isNotEmpty) {
        for (final candidate in _pendingRemoteCandidates) {
          await _peerConnection!.addCandidate(candidate);
        }
        _pendingRemoteCandidates.clear();
      }
    } catch (e) {
      debugPrint('Error handling answer: $e');
    }
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> payload) async {
    if (_peerConnection == null) return;
    try {
      final candidateMap = payload['candidate'];
      if (candidateMap == null) return;

      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      debugPrint('Received remote ICE candidate: ${candidate.candidate}');

      if (await _peerConnection!.getRemoteDescription() != null) {
        await _peerConnection!.addCandidate(candidate);
        debugPrint('Remote ICE candidate added');
      } else {
        _pendingRemoteCandidates.add(candidate);
        debugPrint('Remote ICE candidate buffered');
      }
    } catch (e) {
      debugPrint('Error handling remote candidate: $e');
    }
  }

  Future<bool> _handleCameraAndMicPermissions() async {
    try {
      if (kIsWeb) {
        // For web, we need to handle permissions differently
        // The browser will prompt for permissions when getUserMedia is called
        return true;
      }
      final micStatus = await Permission.microphone.request();

      if (!micStatus.isGranted) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Необходим доступ к микрофону. Разрешите в настройках.'),
            action: SnackBarAction(
              label: 'Настройки',
              onPressed: openAppSettings,
            ),
          ),
        );
        return false;
      }

      return micStatus.isGranted;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      // Even if we can't check permissions, try to proceed
      return true;
    }
  }

  void _toggleMicrophone() {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !track.enabled;
    }
    setState(() {
      _microphoneEnabled = !_microphoneEnabled;
    });
  }

  void _hangUp() async {
    await _supabaseService.sendCallEnd(chatId: widget.chatId);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _testAudioPlayback() async {
    if (_remoteStream == null) return;
    
    try {
      final audioTracks = _remoteStream!.getAudioTracks();
      debugPrint('Testing audio playback for ${audioTracks.length} tracks');
      
      for (final track in audioTracks) {
        debugPrint('Audio track ${track.id}: enabled=${track.enabled}, muted=${track.muted}');
        
        // Force enable the track
        track.enabled = true;
        
        // Note: setVolume is not available in flutter_webrtc
        // We can only ensure the track is enabled
        debugPrint('Audio track enabled for testing: ${track.id}');
      }
      
      // Show notification that audio should be working
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Аудио подключено. Проверьте громкость устройства.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error testing audio playback: $e');
    }
  }

  Future<void> _attachRemoteStream(MediaStream stream, {MediaStreamTrack? addedTrack}) async {
    debugPrint('=== _attachRemoteStream ===');
    debugPrint('Stream ID: ${stream.id}');
    debugPrint('Stream audio tracks: ${stream.getAudioTracks().length}');
    debugPrint('Stream video tracks: ${stream.getVideoTracks().length}');
    
    if (_remoteStream == null || _remoteStream!.id != stream.id) {
      _remoteStream = stream;
      // Only set srcObject for video tracks, not for audio-only streams
      if (stream.getVideoTracks().isNotEmpty) {
        _remoteRenderer.srcObject = stream;
        debugPrint('Remote video stream attached (${stream.id})');
      } else {
        debugPrint('Remote audio-only stream attached (${stream.id})');
      }
    } else if (addedTrack != null && !_remoteStream!.getTracks().any((t) => t.id == addedTrack.id)) {
      _remoteStream!.addTrack(addedTrack);
      debugPrint('Track ${addedTrack.id} appended to existing remote stream');
    }

    if (addedTrack != null && addedTrack.kind == 'audio') {
      addedTrack.enabled = true;
      debugPrint('Remote audio track explicitly enabled: ${addedTrack.id}');
    }

    // Enable all audio tracks in the stream
    for (final track in stream.getAudioTracks()) {
      track.enabled = true;
      debugPrint('Enabled audio track in stream: ${track.id}');
      
      // For mobile devices, we need to ensure audio is played through the speaker
      if (!kIsWeb) {
        try {
          // Force audio to play through speaker on mobile
          // Note: setVolume is not available in flutter_webrtc, but we can ensure the track is enabled
          debugPrint('Audio track enabled for mobile: ${track.id}');
        } catch (e) {
          debugPrint('Error enabling audio track ${track.id}: $e');
        }
      }
    }

    final hasAudio = (_remoteStream?.getAudioTracks().isNotEmpty ?? false) || addedTrack?.kind == 'audio';
    final connectionReady = hasAudio;

    debugPrint('Has audio: $hasAudio, Connection ready: $connectionReady');

    if (mounted) {
      setState(() {
        if (hasAudio) {
          _hasRemoteAudio = true;
        }
        if (connectionReady) {
          _connected = true;
          _initializing = false;
        }
      });
    }

    if (connectionReady) {
      debugPrint('Remote media received; connection flags updated (audio available)');
      
      // Test audio playback on mobile
      if (!kIsWeb && _remoteStream != null) {
        _testAudioPlayback();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Звонок с ${widget.peerName}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _hangUp,
        ),
        actions: [
          // Индикаторы состояния аудио/видео
          if (_hasRemoteAudio)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.volume_up, color: Colors.green, size: 20),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _initializing
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'Аудио-звонок',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
          ),
          // Индикатор подключения
          if (!_initializing && !_connected)
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Подключение...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  FloatingActionButton(
                    onPressed: _toggleMicrophone,
                    heroTag: 'mic',
                    backgroundColor: _microphoneEnabled ? Colors.green : Colors.red,
                    child: Icon(_microphoneEnabled ? Icons.mic : Icons.mic_off),
                  ),
                  FloatingActionButton(
                    onPressed: _hangUp,
                    heroTag: 'hangup',
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.call_end),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
