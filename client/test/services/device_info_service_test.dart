import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/device/device_info_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceInfo (model)', () {
    test('constructs with default values', () {
      final info = DeviceInfo();
      expect(info.platformType, 'unknown');
      expect(info.osVersion, '');
      expect(info.deviceModel, '');
      expect(info.deviceBrand, '');
      expect(info.appVersion, '');
      expect(info.appBuildNumber, '');
    });

    test('constructs with provided values', () {
      final info = DeviceInfo(
        platformType: 'web',
        osVersion: '12.0',
        deviceModel: 'Chrome',
        deviceBrand: 'Google',
        appVersion: '0.1.0',
        appBuildNumber: '1',
      );
      expect(info.platformType, 'web');
      expect(info.osVersion, '12.0');
      expect(info.deviceModel, 'Chrome');
      expect(info.deviceBrand, 'Google');
      expect(info.appVersion, '0.1.0');
      expect(info.appBuildNumber, '1');
    });
  });

  group('DeviceInfoService', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel('dev.fluttercommunity.plus/package_info'),
        (MethodCall methodCall) async {
          return <String, dynamic>{
            'appName': 'Stealth',
            'packageName': 'com.stealth.app',
            'version': '0.1.0',
            'buildNumber': '1',
          };
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel('dev.fluttercommunity.plus/package_info'),
        null,
      );
    });

    test('instance is a singleton', () {
      final a = DeviceInfoService.instance;
      final b = DeviceInfoService.instance;
      expect(identical(a, b), isTrue);
    });

    test('getDeviceInfo falls back to Platform.operatingSystem on plugin failure',
        () async {
      final info = await DeviceInfoService.instance.getDeviceInfo();
      expect(info.platformType, isNot('unknown'));
      expect(info.appVersion, '0.1.0');
      expect(info.appBuildNumber, '1');
    });

    test('getDeviceInfo does not crash when device_info_plus is unavailable',
        () async {
      final info = await DeviceInfoService.instance.getDeviceInfo();
      expect(info, isA<DeviceInfo>());
    });
  });
}
