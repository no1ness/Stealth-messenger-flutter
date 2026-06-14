import 'package:package_info_plus/package_info_plus.dart';
import 'package:stealth/logging/logger.dart';

class AppMetadata {
  const AppMetadata({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get displayVersion {
    if (version == 'unknown' || buildNumber == 'unknown') {
      return 'version unknown';
    }
    return '$version+$buildNumber';
  }
}

class AppMetadataService {
  const AppMetadataService();

  Future<AppMetadata> load() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final metadata = AppMetadata(
        version: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
      );
      Logger.debug('[bootstrap] app version loaded', extras: {
        'version': metadata.displayVersion,
      });
      return metadata;
    } catch (error) {
      Logger.warn('[bootstrap] app version unavailable', extras: {
        'error': error,
      });
      return const AppMetadata(version: 'unknown', buildNumber: 'unknown');
    }
  }
}
