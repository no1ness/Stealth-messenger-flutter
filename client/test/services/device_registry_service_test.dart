import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/device/device_registry_service.dart';

void main() {
  group('DeviceRegistryService', () {
    test('instance is a singleton', () {
      final a = DeviceRegistryService.instance;
      final b = DeviceRegistryService.instance;
      expect(identical(a, b), isTrue);
    });

    test('deviceId returns unknown before init', () {
      expect(DeviceRegistryService.instance.deviceId, 'unknown');
    });

    test('installCount returns 0 before init', () {
      expect(DeviceRegistryService.instance.installCount, 0);
    });
  });
}
