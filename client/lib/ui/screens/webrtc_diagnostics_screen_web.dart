import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stealth/themes/apple_liquid/theme_exports.dart';
import 'package:stealth/webrtc_support.dart';
import 'package:web/web.dart' as web;

class WebRTCDiagnosticsScreen extends StatefulWidget {
  const WebRTCDiagnosticsScreen({super.key});

  @override
  State<WebRTCDiagnosticsScreen> createState() =>
      _WebRTCDiagnosticsScreenState();
}

class _WebRTCDiagnosticsScreenState extends State<WebRTCDiagnosticsScreen> {
  web.MediaStream? _localStream;
  final bool _isInitialized = true;
  String _status = 'Idle';
  String _error = '';
  String _connectivityStatus = 'Idle';
  String _supportSummary = 'Checking environment...';
  List<String> _blockingIssues = const <String>[];
  bool _isSecureContext = false;
  bool _hasMediaDevices = false;
  bool _hasPeerConnection = false;
  int _audioInputCount = 0;
  String _platformLabel = 'Unknown browser';

  @override
  void initState() {
    super.initState();
    _loadSupport();
  }

  @override
  void dispose() {
    _stopTracks();
    super.dispose();
  }

  Future<void> _loadSupport() async {
    final support = await getWebRTCSupport();
    if (!mounted) {
      return;
    }

    setState(() {
      _supportSummary = support.summary;
      _blockingIssues = support.blockingIssues;
      _isSecureContext = support.isSecureContext;
      _hasMediaDevices = support.hasMediaDevices;
      _hasPeerConnection = support.hasPeerConnection;
      _audioInputCount = support.audioInputCount;
      _platformLabel = support.platformLabel;
    });
  }

  Future<void> _testConnectivity() async {
    setState(() => _connectivityStatus = 'Checking STUN...');
    if (_blockingIssues.isNotEmpty) {
      setState(() {
        _connectivityStatus = _blockingIssues.join(' ');
      });
      return;
    }
    web.RTCPeerConnection? peerConnection;
    final candidates = <web.RTCIceCandidate>[];

    try {
      peerConnection = web.RTCPeerConnection(
        web.RTCConfiguration(
          iceServers: <web.RTCIceServer>[
            web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
          ].toJS,
        ),
      );

      peerConnection.onicecandidate = ((web.Event event) {
        final iceEvent = event as web.RTCPeerConnectionIceEvent;
        final candidate = iceEvent.candidate;
        if (candidate == null || candidate.candidate.isEmpty) {
          return;
        }
        candidates.add(candidate);
        if (mounted) {
          setState(() {
            _connectivityStatus = 'Gathering... (${candidates.length})';
          });
        }
      }).toJS;

      peerConnection.createDataChannel('test');
      final offer = await peerConnection.createOffer().toDart;
      if (offer != null) {
        await peerConnection
            .setLocalDescription(
              web.RTCLocalSessionDescriptionInit(
                type: offer.type,
                sdp: offer.sdp,
              ),
            )
            .toDart;
      }

      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) {
        return;
      }

      setState(() {
        _connectivityStatus = candidates.isNotEmpty
            ? 'Success: ${candidates.length} candidates found'
            : 'Failed: No candidates gathered';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _connectivityStatus = 'Error: $error');
      }
    } finally {
      peerConnection?.close();
    }
  }

  Future<void> _startTest() async {
    setState(() {
      _status = 'Requesting permissions...';
      _error = '';
    });

    try {
      if (_blockingIssues.isNotEmpty) {
        throw Exception(_blockingIssues.join(' '));
      }
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              audio: true.toJS,
              video: false.toJS,
            ),
          )
          .toDart;
      _localStream = stream;
      final audioTracks = stream.getAudioTracks().toDart;
      if (audioTracks.isEmpty) {
        throw Exception('No audio track found');
      }
      final track = audioTracks.first;
      if (!mounted) {
        return;
      }

      setState(() {
        _status =
            'Audio track active: ${track.label}\nEnabled: ${track.enabled}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Error';
        _error = error.toString();
      });
    }
  }

  Future<void> _stopTest() async {
    _stopTracks();
    if (mounted) {
      setState(() => _status = 'Stopped');
    }
  }

  void _stopTracks() {
    for (final track in _localStream?.getTracks().toDart ?? const []) {
      track.stop();
    }
    _localStream = null;
  }

  String _buildDiagnosticsSummary() {
    final issues =
        _blockingIssues.isEmpty ? 'none' : _blockingIssues.join(' | ');
    return [
      'support=$_supportSummary',
      'secure_context=$_isSecureContext',
      'media_devices=$_hasMediaDevices',
      'peer_connection=$_hasPeerConnection',
      'audio_inputs=$_audioInputCount',
      'browser=$_platformLabel',
      'mic_status=$_status',
      'connectivity_status=$_connectivityStatus',
      'blocking_issues=$issues',
    ].join('\n');
  }

  Future<void> _copyDiagnosticsSummary() async {
    await Clipboard.setData(
      ClipboardData(text: _buildDiagnosticsSummary()),
    );
    if (!mounted) {
      return;
    }
    showStealthSnackBar(context, 'Диагностика скопирована',
        kind: SnackKind.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(title: 'Диагностика WebRTC', showBackButton: true),
      ),
      body: StealthAnimatedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                GlassContainer(
                  child: Column(
                    children: [
                      const SectionHeader(
                        title: 'Тест микрофона',
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      ),
                      if (_error.isNotEmpty)
                        Text(
                          _error,
                          style: AppTypography.body.copyWith(
                            color: AppColors.systemRed,
                          ),
                          textAlign: TextAlign.center,
                        )
                      else
                        Text(
                          _status,
                          style: AppTypography.body,
                          textAlign: TextAlign.center,
                        ),
                      if (_blockingIssues.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _blockingIssues.join('\n'),
                          style: AppTypography.caption1.copyWith(
                            color: AppColors.systemRed,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _startTest,
                            icon: const Icon(Icons.mic),
                            label: const Text('Начать тест'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _stopTest,
                            icon: const Icon(Icons.stop),
                            label: const Text('Остановить'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loadSupport,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Обновить'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _copyDiagnosticsSummary,
                            icon: const Icon(Icons.copy_all),
                            label: const Text('Копировать сводку'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                GlassContainer(
                  child: Column(
                    children: [
                      const SectionHeader(
                        title: 'Тест соединения',
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      ),
                      Text(
                        _connectivityStatus,
                        textAlign: TextAlign.center,
                        style: AppTypography.body,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton.icon(
                        onPressed: _testConnectivity,
                        icon: const Icon(Icons.network_check),
                        label: const Text('Тест STUN/ICE'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _loadSupport,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Перезагрузить окружение'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _copyDiagnosticsSummary,
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Копировать сводку'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                GlassContainer(
                  child: Column(
                    children: [
                      const SectionHeader(
                        title: 'Системная информация',
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      ),
                      _buildInfoRow('Browser WebRTC', 'Enabled'),
                      _buildInfoRow('Support', _supportSummary),
                      _buildInfoRow(
                        'Secure context',
                        _isSecureContext ? 'Yes' : 'No',
                      ),
                      _buildInfoRow(
                        'MediaDevices API',
                        _hasMediaDevices ? 'Available' : 'Missing',
                      ),
                      _buildInfoRow(
                        'RTCPeerConnection',
                        _hasPeerConnection ? 'Available' : 'Missing',
                      ),
                      _buildInfoRow(
                        'Audio inputs',
                        _audioInputCount.toString(),
                      ),
                      _buildInfoRow('Browser', _platformLabel),
                      _buildInfoRow(
                        'Platform',
                        Theme.of(context).platform.toString(),
                      ),
                      _buildInfoRow(
                        'Diagnostics Ready',
                        _isInitialized.toString(),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
