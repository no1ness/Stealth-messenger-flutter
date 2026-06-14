import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/ui/screens/app_update/update_prompt_screen.dart';

void main() {
  group('UpdatePromptScreen', () {
    testWidgets('renders optional update with skip action', (tester) async {
      var skipped = false;
      var updated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePromptScreen(
            status: _status(mandatory: false),
            onUpdateNow: () async => updated = true,
            onSkip: () => skipped = true,
          ),
        ),
      );

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Current: 0.1.0+1\nLatest: 0.2.0+2'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Update now'));
      await tester.pump();
      expect(updated, isTrue);

      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(skipped, isTrue);
    });

    testWidgets('renders mandatory update without skip action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePromptScreen(
            status: _status(mandatory: true),
            onUpdateNow: () async {},
            onSkip: () {},
          ),
        ),
      );

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);
    });
  });
}

AppUpdateStatus _status({required bool mandatory}) {
  final current = AppUpdateVersion(version: '0.1.0', buildNumber: 1);
  final manifest = AppUpdateManifest(
    latestVersion: AppUpdateVersion(version: '0.2.0', buildNumber: 2),
    apkUrl: Uri.parse('https://updates.example.com/stealth.apk'),
    sha256: 'e' * 64,
    mandatory: mandatory,
    releaseNotes: 'Release notes',
  );
  return AppUpdateStatus.resolve(
    currentVersion: current,
    manifest: manifest,
    platformSupported: true,
  );
}
