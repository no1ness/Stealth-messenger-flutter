import 'package:flutter/material.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class WebRTCDiagnosticsScreen extends StatelessWidget {
  const WebRTCDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(
          title: 'WebRTC Diagnostics',
          showBackButton: true,
        ),
      ),
      body: StealthAnimatedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: GlassContainer(
              child: Text(
                'Diagnostics are disabled in WebAssembly-safe web mode.',
                style: AppTypography.body,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
