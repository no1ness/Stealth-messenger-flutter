import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/themes/apple_liquid/widgets/call/call_hud_overlay.dart';
import 'package:stealth/themes/apple_liquid/widgets/status_chip.dart';

void main() {
  testWidgets('renders duration and connection status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallHudOverlay(
            duration: '00:42',
            connectionLabel: 'GOOD',
            connectionKind: StatusKind.success,
          ),
        ),
      ),
    );

    expect(find.text('00:42'), findsOneWidget);
    expect(find.text('GOOD'), findsOneWidget);
  });

  testWidgets('renders safety number when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallHudOverlay(
            duration: '01:30',
            connectionLabel: 'FAIR',
            connectionKind: StatusKind.warn,
            safetyNumber: 'A2:5F · 90:1B · 7C:E4 · 31:88',
          ),
        ),
      ),
    );

    expect(find.text('A2:5F · 90:1B · 7C:E4 · 31:88'), findsOneWidget);
  });

  testWidgets('renders telemetry strip when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallHudOverlay(
            duration: '05:00',
            connectionLabel: 'POOR',
            connectionKind: StatusKind.danger,
            telemetry: {
              'Transport': 'RELAY',
              'Audio': 'OPUS',
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('TRANSPORT'), findsOneWidget);
    expect(find.text('RELAY'), findsOneWidget);
    expect(find.textContaining('AUDIO'), findsOneWidget);
    expect(find.text('OPUS'), findsOneWidget);
  });

  testWidgets('renders avatar with halo when provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallHudOverlay(
            duration: '00:10',
            connectionLabel: 'GOOD',
            connectionKind: StatusKind.success,
            avatarWidget: const CircleAvatar(
              radius: 50,
              child: Text('A'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('handles empty telemetry gracefully', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallHudOverlay(
            duration: '00:00',
            connectionLabel: 'GOOD',
            connectionKind: StatusKind.success,
            telemetry: {},
          ),
        ),
      ),
    );

    expect(find.text('00:00'), findsOneWidget);
  });
}
