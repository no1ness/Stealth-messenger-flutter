import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../logging/logger.dart';
import 'device_info.dart';

class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  Future<DeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    String platformType = 'unknown';
    String osVersion = '';
    String deviceModel = '';
    String deviceBrand = '';

    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        platformType = 'android';
        final info = await plugin.androidInfo;
        osVersion = info.version.release;
        deviceModel = info.model;
        deviceBrand = info.brand;
      } else if (Platform.isIOS) {
        platformType = 'ios';
        final info = await plugin.iosInfo;
        osVersion = info.systemVersion;
        deviceModel = info.model;
        deviceBrand = info.name;
      } else if (Platform.isMacOS) {
        platformType = 'macos';
        final info = await plugin.macOsInfo;
        osVersion = info.osRelease;
        deviceModel = info.model;
        deviceBrand = 'Apple';
      } else if (Platform.isLinux) {
        platformType = 'linux';
        final info = await plugin.linuxInfo;
        osVersion = info.version.toString();
        deviceModel = info.name;
        deviceBrand = '';
      } else if (Platform.isWindows) {
        platformType = 'windows';
        final info = await plugin.windowsInfo;
        osVersion = info.computerName;
        deviceModel = info.productName;
        deviceBrand = 'Microsoft';
      }
      Logger.debug('[deviceInfo] platform detected',
          extras: {'platform': platformType, 'model': deviceModel});
    } catch (error) {
      platformType = Platform.operatingSystem;
      Logger.warn('[deviceInfo] detection failed, using fallback',
          extras: {'error': error});
    }

    return DeviceInfo(
      platformType: platformType,
      osVersion: osVersion,
      deviceModel: deviceModel,
      deviceBrand: deviceBrand,
      appVersion: packageInfo.version,
      appBuildNumber: packageInfo.buildNumber,
    );
  }
}
