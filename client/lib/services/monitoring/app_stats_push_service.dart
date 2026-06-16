import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/dashboard/dashboard_service.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';

class AppStatsPushService {
  AppStatsPushService({
    PocketBase? pocketBase,
    Future<Map<String, dynamic>> Function()? statsProvider,
  })  : _pb = pocketBase ?? PocketBaseClient.instance.pb,
        _statsProvider = statsProvider ?? (() => DashboardService().getDashboardSummary());

  final PocketBase _pb;
  final Future<Map<String, dynamic>> Function() _statsProvider;

  bool _pushedOnce = false;

  Future<void> pushStats() async {
    try {
      final summary = await _statsProvider();

      final body = <String, dynamic>{
        'userId': summary['userId']?.toString() ?? '',
        'deviceId': summary['deviceId']?.toString() ?? '',
        'platformType': summary['platformType']?.toString() ?? '',
        'osVersion': summary['osVersion']?.toString() ?? '',
        'deviceModel': summary['deviceModel']?.toString() ?? '',
        'deviceBrand': summary['deviceBrand']?.toString() ?? '',
        'appVersion': summary['appVersion']?.toString() ?? '',
        'appBuildNumber': summary['appBuildNumber']?.toString() ?? '',
        'chatCount': summary['chatCount'] ?? 0,
        'contactCount': summary['contactCount'] ?? 0,
        'messageCount': summary['messageCount'] ?? 0,
        'callCount': summary['callCount'] ?? 0,
        'installCount': summary['installCount'] ?? 0,
      };

      await _pb.collection('app_stats').create(body: body);

      if (!_pushedOnce) {
        _pushedOnce = true;
        Logger.info('[stats-push] first stats pushed to PocketBase',
            extras: {'userId': body['userId']});
      } else {
        Logger.debug('[stats-push] stats pushed',
            extras: {'chatCount': body['chatCount'], 'messageCount': body['messageCount']});
      }
    } catch (error) {
      Logger.warn('[stats-push] failed to push stats',
          extras: {'error': error});
    }
  }
}
