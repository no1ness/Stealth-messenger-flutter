import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_snack_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/call/call_hud_overlay.dart';
import 'package:stealth/themes/apple_liquid/widgets/status_chip.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';
import 'package:stealth/ui/screens/calls/web_call_controller.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';

class WebRTCCallScreen extends StatefulWidget {
  final String peerName;
  final String chatId;
  final bool isCaller;
  final bool isVideoCall;

  /// Уже принятый offer от другого пира (Map с ключами `sdp` и `type`).
  /// Передаётся `CallManager` callee'у при открытии экрана, чтобы избежать
  /// race condition подписки. Для caller всегда `null`.
  final Map<String, dynamic>? initialOffer;

  /// UUID звонящего; заполняется только для callee.
  final String? callerUserId;

  const WebRTCCallScreen({
    super.key,
    required this.peerName,
    required this.chatId,
    required this.isCaller,
    this.isVideoCall = false,
    this.initialOffer,
    this.callerUserId,
  });

  @override
  State<WebRTCCallScreen> createState() => _WebRTCCallScreenState();
}

class _WebRTCCallScreenState extends State<WebRTCCallScreen> {
  late final WebCallController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebCallController(
      chatId: widget.chatId,
      isCaller: widget.isCaller,
      isVideoCall: widget.isVideoCall,
      initialOffer: widget.initialOffer,
      callerUserId: widget.callerUserId,
      onError: _showSnackBar,
      onClose: _popIfPossible,
    );
    // Fire-and-forget: initialize() runs async; первый frame рендерится
    // до её завершения. Lazy signaling init защищает widget-тесты без
    // dotenv (см. контроллер).
    // ignore: discarded_futures
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    showStealthSnackBar(context, message, kind: SnackKind.danger);
  }

  void _popIfPossible() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildScreen(),
    );
  }

  Widget _buildScreen() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        Logger.debug('[stealth-call] web PopScope', extras: {
          'didPop': didPop,
          'isCaller': widget.isCaller,
          'connected': _controller.connected,
          'closing': _controller.closing,
        });
        if (!didPop) await _controller.hangUp();
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
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white),
                        onPressed: _controller.hangUp,
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                // Signature in-call HUD — shared widget across native + web.
                CallHudOverlay(
                  duration: _controller.connected
                      ? _formatDuration(_controller.callDurationSeconds)
                      : _controller.initializing
                          ? 'Connecting…'
                          : 'Calling…',
                  connectionLabel: _controller.connected
                      ? 'CONNECTED'
                      : 'NEGOTIATING',
                  connectionKind: _controller.connected
                      ? StatusKind.success
                      : StatusKind.pending,
                ),
                const Spacer(),
                if (widget.isVideoCall) _buildVideoArea() else _buildAvatar(),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  widget.peerName,
                  style: AppTypography.largeTitle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_controller.setupError != null) _buildSetupErrorPanel(),
                _buildStatusChips(),
                const Spacer(),
                _buildControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 260,
          color: Colors.black.withValues(alpha: 0.35),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_controller.media.hasRemoteVideo)
                HtmlElementView(viewType: _controller.remoteViewType)
              else
                Center(
                  child: Text(
                    'Waiting for video...',
                    style: AppTypography.body.copyWith(color: Colors.white70),
                  ),
                ),
              Positioned(
                right: 12,
                top: 12,
                child: SizedBox(
                  width: 100,
                  height: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black54,
                      child: _controller.media.hasLocalVideo
                          ? HtmlElementView(viewType: _controller.localViewType)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
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
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSetupErrorPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          Text(
            _controller.setupError!,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.systemRed),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _controller.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WebRTCDiagnosticsScreen(),
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
    );
  }

  Widget _buildStatusChips() {
    final iceConnected = _controller.iceConnectionState == 'connected' ||
        _controller.iceConnectionState == 'completed';
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: [
        _buildStatusChip(
          label: _controller.connected ? 'Connected' : 'Negotiating',
          active: _controller.connected,
        ),
        _buildStatusChip(
          label: _controller.microphoneEnabled ? 'Mic on' : 'Mic muted',
          active: _controller.microphoneEnabled,
        ),
        _buildStatusChip(
          label: _controller.speakerEnabled ? 'Speaker on' : 'Speaker off',
          active: _controller.speakerEnabled,
        ),
        _buildStatusChip(
          label: 'ICE: ${_controller.iceConnectionState}',
          active: iceConnected,
        ),
        _buildStatusChip(
          label: 'Signal: ${_controller.signalingState}',
          active: _controller.signalingState == 'stable',
        ),
        _buildStatusChip(
          label: 'Peer: ${_controller.connectionState}',
          active: _controller.connectionState == 'connected',
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.isVideoCall)
            _buildControlButton(
              icon: _controller.cameraEnabled
                  ? Icons.videocam
                  : Icons.videocam_off,
              color: _controller.cameraEnabled
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white,
              iconColor:
                  _controller.cameraEnabled ? Colors.white : Colors.black,
              onPressed: _controller.toggleCamera,
            ),
          _buildControlButton(
            icon: _controller.microphoneEnabled ? Icons.mic : Icons.mic_off,
            color: _controller.microphoneEnabled
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white,
            iconColor:
                _controller.microphoneEnabled ? Colors.white : Colors.black,
            onPressed: _controller.toggleMicrophone,
          ),
          _buildControlButton(
            icon: Icons.call_end,
            color: AppColors.systemRed,
            iconColor: Colors.white,
            size: 72,
            onPressed: _controller.hangUp,
          ),
          _buildControlButton(
            icon:
                _controller.speakerEnabled ? Icons.volume_up : Icons.volume_off,
            color: _controller.speakerEnabled
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white,
            iconColor: _controller.speakerEnabled ? Colors.white : Colors.black,
            onPressed: _controller.toggleSpeaker,
          ),
        ],
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
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
