import 'package:flutter/material.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_container.dart';
import 'package:stealth/themes/apple_liquid/widgets/stealth_background.dart';

class WebRTCCallScreen extends StatelessWidget {
  final String peerName;
  final String chatId;
  final bool isCaller;
  final bool isVideoCall;

  const WebRTCCallScreen({
    super.key,
    required this.peerName,
    required this.chatId,
    required this.isCaller,
    this.isVideoCall = false,
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
