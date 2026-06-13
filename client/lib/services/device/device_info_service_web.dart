import 'package:package_info_plus/package_info_plus.dart';
import 'package:web/web.dart' as web;

import 'device_info.dart';

class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  Future<DeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final userAgent = web.window.navigator.userAgent.toLowerCase();
    String platformType = 'web';
    String osVersion = '';
    String deviceModel = '';
    String deviceBrand = '';

    if (userAgent.contains('android')) {
      platformType = 'android';
      deviceBrand = 'Android';
    } else if (userAgent.contains('iphone') || userAgent.contains('ipad')) {
      platformType = 'ios';
      deviceBrand = 'Apple';
    } else if (userAgent.contains('mac')) {
      platformType = 'macos';
      deviceBrand = 'Apple';
    } else if (userAgent.contains('windows')) {
      platformType = 'windows';
      deviceBrand = 'Microsoft';
    } else if (userAgent.contains('linux')) {
      platformType = 'linux';
      deviceBrand = 'Linux';
    }

    if (userAgent.contains('chrome')) {
      deviceModel = 'Chrome';
    } else if (userAgent.contains('firefox')) {
      deviceModel = 'Firefox';
    } else if (userAgent.contains('safari')) {
      deviceModel = 'Safari';
    } else if (userAgent.contains('edge')) {
      deviceModel = 'Edge';
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
