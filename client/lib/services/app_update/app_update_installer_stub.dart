import 'app_update_models.dart';

typedef AppUpdateInstallStateListener = void Function(
    AppUpdateInstallState state);

class AppUpdateInstaller {
  const AppUpdateInstaller();

  Future<void> installUpdate(
    AppUpdateManifest manifest, {
    AppUpdateInstallStateListener? onState,
  }) async {
    onState?.call(
      const AppUpdateInstallState(
        phase: AppUpdateInstallPhase.failed,
        detail: 'APK updates are supported only on Android.',
      ),
    );
    throw UnsupportedError('APK updates are supported only on Android');
  }
}
