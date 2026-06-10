import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/ui/screens/app_update/update_status_card.dart';

void main() {
  testWidgets('UpdateStatusCard renders version and update action',
      (tester) async {
    var checked = false;
    var installed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateStatusCard(
            appVersionLabel: '0.1.0+1',
            status: _status(),
            installState: null,
            isCheckingUpdate: false,
            isInstallingUpdate: false,
            onCheckForUpdates: () => checked = true,
            onInstallUpdate: () => installed = true,
          ),
        ),
      ),
    );

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Stealth 0.1.0+1'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    expect(checked, isTrue);

    await tester.tap(find.text('Update now'));
    await tester.pump();
    expect(installed, isTrue);
  });

  testWidgets('UpdateStatusCard hides install button when up to date',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateStatusCard(
            appVersionLabel: '0.2.0+2',
            status: AppUpdateStatus.resolve(
              currentVersion:
                  AppUpdateVersion(version: '0.2.0', buildNumber: 2),
              manifest: _manifest(),
              platformSupported: true,
            ),
            installState: null,
            isCheckingUpdate: false,
            isInstallingUpdate: false,
            onCheckForUpdates: () {},
            onInstallUpdate: () {},
          ),
        ),
      ),
    );

    expect(find.text('You are up to date\nLatest: 0.2.0+2'), findsOneWidget);
    expect(find.text('Update now'), findsNothing);
  });
}

AppUpdateStatus _status() {
  return AppUpdateStatus.resolve(
    currentVersion: AppUpdateVersion(version: '0.1.0', buildNumber: 1),
    manifest: _manifest(),
    platformSupported: true,
  );
}

AppUpdateManifest _manifest() {
  return AppUpdateManifest(
    latestVersion: AppUpdateVersion(version: '0.2.0', buildNumber: 2),
    apkUrl: Uri.parse('https://updates.example.com/stealth.apk'),
    sha256: 'f' * 64,
    mandatory: false,
    releaseNotes: 'Release notes',
  );
}
