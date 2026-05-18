import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/call/call_hud_overlay.dart';
import 'package:stealth/themes/apple_liquid/widgets/status_chip.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';
import 'package:stealth/ui/screens/calls/native_call_controller.dart';

class WebRTCCallScreen extends StatefulWidget {
  final String peerName;
  final String chatId;
  final bool isCaller;
  final bool isVideoCall;

  /// Уже принятый offer от другого пира как plain Map с ключами `sdp`
  /// и `type`. Передаётся `CallManager` при открытии экрана callee,
  /// чтобы избежать race condition подписки. Для caller всегда `null`.
  ///
  /// Map (а не `RTCSessionDescription`) выбран для совместимости с
  /// web-имплементацией, которая не использует `flutter_webrtc`.
  final Map<String, dynamic>? initialOffer;

  /// UUID звонящего (caller). Заполняется только для callee — для caller
  /// определяется через `PeerResolver`. Используется как `targetUserId`
  /// при отправке answer/ICE/hangup.
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
  late final NativeCallController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NativeCallController(
      chatId: widget.chatId,
      isCaller: widget.isCaller,
      isVideoCall: widget.isVideoCall,
      initialOffer: widget.initialOffer,
      callerUserId: widget.callerUserId,
      onError: _showSnackBar,
      onClose: _popIfPossible,
    );
    // Fire-and-forget: initialize() runs async; semantics-тест проходит на
    // первом frame, не дожидаясь её завершения. См. контроллер про lazy
    // signaling init.
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
        Logger.info('[stealth-call] PopScope', extras: {
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
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
                // Signature in-call HUD — mono duration + E2E ENCRYPTED
                // badge with scanline + connection-quality chip.
                Semantics(
                  label: AccessibilityIds.callStatus,
                  liveRegion: true,
                  child: CallHudOverlay(
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
                ),
                const Spacer(),
                if (widget.isVideoCall) _buildVideoArea() else _buildAvatar(),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  widget.peerName,
                  style: AppTypography.largeTitle.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    _buildStatusChip(
                        label: _controller.microphoneEnabled
                            ? 'Mic on'
                            : 'Mic muted',
                        active: _controller.microphoneEnabled),
                    _buildStatusChip(
                        label: _controller.speakerEnabled
                            ? 'Speaker on'
                            : 'Speaker off',
                        active: _controller.speakerEnabled),
                  ],
                ),
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
    final remoteStream = _controller.media.remoteStream;
    final localStream = _controller.media.localStream;
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
              if (remoteStream != null &&
                  remoteStream.getVideoTracks().isNotEmpty)
                RTCVideoView(
                  _controller.media.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                Center(
                  child: Text(
                    'Waiting for video...',
                    style:
                        AppTypography.body.copyWith(color: Colors.white70),
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
                      child: (localStream != null &&
                              localStream.getVideoTracks().isNotEmpty)
                          ? RTCVideoView(
                              _controller.media.localRenderer,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            )
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
              color: Colors.white),
        ),
      ),
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
          Semantics(
            label: AccessibilityIds.mute,
            button: true,
            child: _buildControlButton(
              icon: _controller.microphoneEnabled ? Icons.mic : Icons.mic_off,
              color: _controller.microphoneEnabled
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white,
              iconColor: _controller.microphoneEnabled
                  ? Colors.white
                  : Colors.black,
              onPressed: _controller.toggleMicrophone,
            ),
          ),
          Semantics(
            label: AccessibilityIds.hangUp,
            button: true,
            child: _buildControlButton(
              icon: Icons.call_end,
              color: AppColors.systemRed,
              iconColor: Colors.white,
              size: 72,
              onPressed: _controller.hangUp,
            ),
          ),
          Semantics(
            label: AccessibilityIds.speaker,
            button: true,
            child: _buildControlButton(
              icon: _controller.speakerEnabled
                  ? Icons.volume_up
                  : Icons.volume_off,
              color: _controller.speakerEnabled
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white,
              iconColor:
                  _controller.speakerEnabled ? Colors.white : Colors.black,
              onPressed: _controller.toggleSpeaker,
            ),
          ),
          if (widget.isVideoCall)
            _buildControlButton(
              icon: Icons.flip_camera_ios_outlined,
              color: Colors.white.withValues(alpha: 0.2),
              iconColor: Colors.white,
              onPressed: _controller.switchCamera,
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
