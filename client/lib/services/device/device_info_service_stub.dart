import 'package:package_info_plus/package_info_plus.dart';

import 'device_info.dart';

class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  Future<DeviceInfo> getDeviceInfo() async {
    String appVersion = '0.1.0';
    String appBuildNumber = '1';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      appBuildNumber = info.buildNumber;
    } catch (_) {
    }
    return DeviceInfo(
      platformType: 'unknown',
      osVersion: '',
      deviceModel: '',
      deviceBrand: '',
      appVersion: appVersion,
      appBuildNumber: appBuildNumber,
    );
  }
}
