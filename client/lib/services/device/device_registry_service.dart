import 'package:uuid/uuid.dart';

import '../../logging/logger.dart';
import '../../storage_service.dart';

class DeviceRegistryService {
  DeviceRegistryService._();
  static final DeviceRegistryService instance = DeviceRegistryService._();

  String? _cachedDeviceId;
  int _cachedInstallCount = 0;

  String get deviceId => _cachedDeviceId ?? 'unknown';
  int get installCount => _cachedInstallCount;

  Future<void> init() async {
    final storage = StorageService();
    await storage.init();

    final existingId = await storage.read('device_id');
    if (existingId != null && existingId.isNotEmpty) {
      _cachedDeviceId = existingId;
      Logger.debug('[deviceRegistry] existing device restored',
          extras: {'deviceId': existingId});
    } else {
      final newId = const Uuid().v4();
      await storage.write('device_id', newId);
      _cachedDeviceId = newId;
      Logger.info('[deviceRegistry] new device registered',
          extras: {'deviceId': newId});
    }

    final existingCount = await storage.read('install_count');
    if (existingCount != null && existingCount.isNotEmpty) {
      _cachedInstallCount = int.tryParse(existingCount) ?? 0;
    }
    _cachedInstallCount++;
    await storage.write('install_count', _cachedInstallCount.toString());
    Logger.debug('[deviceRegistry] install count',
        extras: {'count': _cachedInstallCount});
  }
}
