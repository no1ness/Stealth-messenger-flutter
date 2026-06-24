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
        child: TgAppBar(
          title: 'WebRTC Diagnostics',
          showBackButton: true,
        ),
      ),
      body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(TgSpacing.md),
            child: FlatContainer(
              child: Text(
                'Diagnostics are disabled in WebAssembly-safe web mode.',
                style: TgTypography.body,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
    );
  }
}
