import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stealth/logging/logger.dart';

import 'app_update_models.dart';
import 'app_update_platform.dart' as app_update_platform;

typedef AppUpdateInstallStateListener = void Function(
    AppUpdateInstallState state);
typedef ApkDownloader = Future<File> Function(
  AppUpdateManifest manifest,
  AppUpdateInstallStateListener? onState,
);

class AppUpdateInstaller {
  AppUpdateInstaller({
    HttpClient Function()? httpClientFactory,
    Future<Directory> Function()? tempDirectoryProvider,
    MethodChannel? channel,
    ApkDownloader? apkDownloader,
    bool Function()? platformSupportedProvider,
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _tempDirectoryProvider = tempDirectoryProvider ?? getTemporaryDirectory,
        _channel = channel ?? const MethodChannel('stealth/app_update'),
        _apkDownloader = apkDownloader,
        _platformSupportedProvider = platformSupportedProvider ??
            (() => app_update_platform.isAndroidInstallerSupported);

  final HttpClient Function() _httpClientFactory;
  final Future<Directory> Function() _tempDirectoryProvider;
  final MethodChannel _channel;
  final ApkDownloader? _apkDownloader;
  final bool Function() _platformSupportedProvider;

  Future<void> installUpdate(
    AppUpdateManifest manifest, {
    AppUpdateInstallStateListener? onState,
  }) async {
    if (!_platformSupportedProvider()) {
      Logger.warn('[app-update] install unsupported platform');
      _emit(
        onState,
        const AppUpdateInstallState(
          phase: AppUpdateInstallPhase.failed,
          detail: 'APK updates are supported only on Android.',
        ),
      );
      throw UnsupportedError('APK updates are supported only on Android');
    }

    final downloader = _apkDownloader;
    final apkFile = downloader == null
        ? await _downloadApk(manifest, onState: onState)
        : await downloader(manifest, onState);
    await _verifySha256(apkFile, manifest, onState: onState);
    await _handoffToInstaller(apkFile, onState: onState);
  }

  Future<File> _downloadApk(
    AppUpdateManifest manifest, {
    AppUpdateInstallStateListener? onState,
  }) async {
    final tempDir = await _tempDirectoryProvider();
    final file = File(
        '${tempDir.path}/stealth-update-${manifest.latestVersion.buildNumber}.apk');
    final client = _httpClientFactory();
    try {
      Logger.info('[app-update] download started');
      final request = await client.getUrl(manifest.apkUrl);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('APK request failed with HTTP ${response.statusCode}');
      }

      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength > 0 ? response.contentLength : null;
      _emit(
        onState,
        AppUpdateInstallState(
          phase: AppUpdateInstallPhase.downloading,
          receivedBytes: received,
          totalBytes: total,
        ),
      );

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        Logger.debug('[app-update] download progress', extras: {
          'received': received,
          'total': total,
        });
        _emit(
          onState,
          AppUpdateInstallState(
            phase: AppUpdateInstallPhase.downloading,
            receivedBytes: received,
            totalBytes: total,
          ),
        );
      }
      await sink.close();
      Logger.info('[app-update] download completed', extras: {
        'bytesReceived': received,
      });
      return file;
    } catch (error) {
      Logger.error('[app-update] download failed', extras: {'error': error});
      _emit(
        onState,
        AppUpdateInstallState(
          phase: AppUpdateInstallPhase.failed,
          detail: '$error',
        ),
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _verifySha256(
    File file,
    AppUpdateManifest manifest, {
    AppUpdateInstallStateListener? onState,
  }) async {
    _emit(
      onState,
      const AppUpdateInstallState(phase: AppUpdateInstallPhase.verifying),
    );
    try {
      final bytes = await file.readAsBytes();
      final hash = await Sha256().hash(bytes);
      final actual = hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      if (actual != manifest.sha256) {
        throw StateError('APK checksum mismatch');
      }
      Logger.info('[app-update] checksum verified');
      _emit(
        onState,
        const AppUpdateInstallState(
            phase: AppUpdateInstallPhase.readyToInstall),
      );
    } catch (error) {
      Logger.error('[app-update] checksum verification failed',
          extras: {'error': error});
      _emit(
        onState,
        AppUpdateInstallState(
          phase: AppUpdateInstallPhase.failed,
          detail: '$error',
        ),
      );
      rethrow;
    }
  }

  Future<void> _handoffToInstaller(
    File file, {
    AppUpdateInstallStateListener? onState,
  }) async {
    _emit(
      onState,
      const AppUpdateInstallState(
        phase: AppUpdateInstallPhase.handingOffToInstaller,
      ),
    );
    try {
      await _channel.invokeMethod<void>('installApk', {'path': file.path});
      Logger.info('[app-update] install handoff completed');
      _emit(
        onState,
        const AppUpdateInstallState(phase: AppUpdateInstallPhase.completed),
      );
    } catch (error) {
      Logger.error('[app-update] install handoff failed',
          extras: {'error': error});
      _emit(
        onState,
        AppUpdateInstallState(
          phase: AppUpdateInstallPhase.failed,
          detail: '$error',
        ),
      );
      rethrow;
    }
  }

  void _emit(
    AppUpdateInstallStateListener? listener,
    AppUpdateInstallState state,
  ) {
    listener?.call(state);
  }
}
