import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';

class MonitoringDataService {
  MonitoringDataService({PocketBase? pocketBase})
      : _pb = pocketBase ?? PocketBaseClient.instance.pb;

  final PocketBase _pb;

  List<Map<String, dynamic>> _cache = [];
  DateTime _lastFetch = DateTime(2000);
  static const Duration _cacheTtl = Duration(seconds: 30);

  Future<List<Map<String, dynamic>>> getAllStats() async {
    if (_cache.isNotEmpty &&
        DateTime.now().difference(_lastFetch) < _cacheTtl) {
      return _cache;
    }
    try {
      final result = await _pb
          .collection('app_stats')
          .getList(page: 1, perPage: 200, sort: '-created');
      _cache = result.items.map((r) => r.data).toList();
      _lastFetch = DateTime.now();
      Logger.debug('[monitoring-data] fetched ${_cache.length} records');
      return _cache;
    } catch (error) {
      Logger.warn('[monitoring-data] fetch failed',
          extras: {'error': error});
      return _cache;
    }
  }

  Future<Map<String, dynamic>> getAggregated() async {
    final records = await getAllStats();
    if (records.isEmpty) {
      return {
        'totalUsers': 0,
        'totalChats': 0,
        'totalMessages': 0,
        'totalCalls': 0,
        'totalContacts': 0,
      };
    }
    final distinctUsers = <String>{};
    var totalChats = 0;
    var totalMessages = 0;
    var totalCalls = 0;
    var totalContacts = 0;
    for (final r in records) {
      distinctUsers.add(r['userId']?.toString() ?? '');
      totalChats += (r['chatCount'] as num?)?.toInt() ?? 0;
      totalMessages += (r['messageCount'] as num?)?.toInt() ?? 0;
      totalCalls += (r['callCount'] as num?)?.toInt() ?? 0;
      totalContacts += (r['contactCount'] as num?)?.toInt() ?? 0;
    }
    return {
      'totalUsers': distinctUsers.length,
      'totalChats': totalChats,
      'totalMessages': totalMessages,
      'totalCalls': totalCalls,
      'totalContacts': totalContacts,
    };
  }

  Future<Map<String, int>> getPlatformBreakdown() async {
    final records = await getAllStats();
    final breakdown = <String, int>{};
    for (final r in records) {
      final platform = r['platformType']?.toString() ?? 'unknown';
      breakdown[platform] = (breakdown[platform] ?? 0) + 1;
    }
    return breakdown;
  }
}
