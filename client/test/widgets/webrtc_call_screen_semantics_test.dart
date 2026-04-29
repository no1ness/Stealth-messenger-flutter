import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stealth/ui/screens/webrtc_call_screen_native_impl.dart';

// Validates: Requirements 5.1, 5.2, 5.3, 5.4

void main() {
  setUpAll(() async {
    // shared_preferences is required by Supabase.initialize() for auth storage.
    SharedPreferences.setMockInitialValues({});

    // Initialize Supabase with a fake URL so that SupabaseService() can be
    // constructed without throwing. No real network calls are made during
    // the widget test — _startCall() fails fast in the test environment.
    await Supabase.initialize(
      url: 'https://fake-project.supabase.co',
      anonKey: 'fake-anon-key',
    );
  });

  testWidgets(
    'WebRTCCallScreen exposes Hang up, Mute, Speaker, and Call status semantics labels',
    (WidgetTester tester) async {
      final handle = tester.ensureSemantics();

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Suppress platform-channel errors from flutter_webrtc / permission_handler
      // that fire during _startCall() in initState. These are expected in the
      // test environment and do not affect the semantics tree produced by build().
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('MissingPluginException') ||
            msg.contains('PlatformException') ||
            msg.contains('overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // Wrap in a nested Navigator so that _startCall()'s error-path
      // Navigator.maybePop() cannot remove the screen (the root route is
      // not poppable).
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => WebRTCCallScreen(
                peerName: 'Alice',
                chatId: 'test-chat-id',
                isCaller: true,
              ),
            ),
          ),
        ),
      );

      // Single pump: renders the first frame (build() runs) without waiting
      // for the async _startCall() to complete. The Semantics nodes are
      // present in build() regardless of connection state.
      await tester.pump();

      // Restore error handler before assertions so test failures propagate.
      FlutterError.onError = originalOnError;

      // Requirement 5.2 — Hang up button
      expect(find.bySemanticsLabel(RegExp('Hang up')), findsOneWidget);

      // Requirement 5.3 — Mute button (use atLeast because status chips may
      // also contain 'Mute' / 'Mic' text that matches the regex)
      expect(find.bySemanticsLabel(RegExp('Mute')), findsAtLeastNWidgets(1));

      // Requirement 5.4 — Speaker button (status chip 'Speaker on' also matches)
      expect(find.bySemanticsLabel(RegExp('Speaker')), findsAtLeastNWidgets(1));

      // Requirement 5.1 — Call status live region
      expect(find.bySemanticsLabel(RegExp('Call status')), findsOneWidget);

      handle.dispose();
    },
  );
}
