import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class WebRTCCallScreen extends StatelessWidget {
  final String peerName;
  final String chatId;
  final bool isCaller;
  final bool isVideoCall;

  /// Сохранены для совместимости с native/web вариантами; в stub-режиме
  /// (WebAssembly safe) звонки недоступны, поэтому значения игнорируются.
  final Map<String, dynamic>? initialOffer;
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
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(
          title: 'Calls unavailable',
          showBackButton: true,
        ),
      ),
      body: StealthAnimatedBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: GlassContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'WebAssembly-safe web mode does not include WebRTC calls yet.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Peer: $peerName', style: AppTypography.caption1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
