import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stealth/themes/tg/tg_colors.dart';

class WebRTCDiagnosticsScreen extends StatefulWidget {
  const WebRTCDiagnosticsScreen({super.key});

  @override
  State<WebRTCDiagnosticsScreen> createState() =>
      _WebRTCDiagnosticsScreenState();
}

class _WebRTCDiagnosticsScreenState extends State<WebRTCDiagnosticsScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _isInitialized = false;
  String _status = 'Idle';
  String _error = '';
  String _connectivityStatus = 'Idle';

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
    if (mounted) setState(() => _isInitialized = true);
  }

  @override
  void dispose() {
    _localStream?.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  Future<void> _testConnectivity() async {
    setState(() => _connectivityStatus = 'Checking STUN...');
    RTCPeerConnection? pc;
    try {
      pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      final candidates = <RTCIceCandidate>[];
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          candidates.add(candidate);
          if (mounted) {
            setState(() {
              _connectivityStatus = 'Gathering... (${candidates.length})';
            });
          }
        }
      };
      await pc.createDataChannel('test', RTCDataChannelInit());
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _connectivityStatus = candidates.isNotEmpty
              ? 'Success: ${candidates.length} candidates found'
              : 'Failed: No candidates gathered';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _connectivityStatus = 'Error: $error');
    } finally {
      await pc?.close();
    }
  }

  Future<void> _startTest() async {
    setState(() {
      _status = 'Requesting permissions...';
      _error = '';
    });
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      _localStream = stream;
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) throw Exception('No audio track found');
      final track = audioTracks.first;
      setState(() {
        _status =
            'Audio track active: ${track.label}\nEnabled: ${track.enabled}';
      });
    } catch (error) {
      setState(() {
        _status = 'Error';
        _error = error.toString();
      });
    }
  }

  Future<void> _stopTest() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    setState(() => _status = 'Stopped');
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
                          style: AppTypography.body
                              .copyWith(color: AppColors.systemRed),
                          textAlign: TextAlign.center,
                        )
                      else
                        Text(
                          _status,
                          style: AppTypography.body,
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                      Text(_connectivityStatus, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton.icon(
                        onPressed: _testConnectivity,
                        icon: const Icon(Icons.network_check),
                        label: const Text('Тест STUN/ICE'),
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
                      _buildInfoRow('Flutter WebRTC', 'Installed'),
                      _buildInfoRow(
                        'Platform',
                        Theme.of(context).platform.toString(),
                      ),
                      _buildInfoRow(
                        'Renderer Initialized',
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
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
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
