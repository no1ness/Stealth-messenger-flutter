import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/monitoring/monitoring_data_service.dart';

class _FakePocketBase extends PocketBase {
  _FakePocketBase() : super('http://fake.local');

  List<Map<String, dynamic>> mockRecords = [];

  @override
  RecordService collection(String collectionIdOrName) {
    return _FakeRecordService(this, collectionIdOrName);
  }
}

class _FakeRecordService extends RecordService {
  final _FakePocketBase _pb;

  _FakeRecordService(super.client, super.collectionIdOrName)
      : _pb = client as _FakePocketBase;

  @override
  Future<ResultList<RecordModel>> getList({
    int page = 1,
    int perPage = 30,
    bool skipTotal = false,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final items = _pb.mockRecords.map((d) => RecordModel(d)).toList();
    return ResultList<RecordModel>(
      page: page,
      perPage: perPage,
      totalItems: items.length,
      totalPages: 1,
      items: items,
    );
  }

  @override
  Future<RecordModel> create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    _pb.mockRecords.add(body);
    return RecordModel(body);
  }
}

void main() {
  group('MonitoringDataService', () {
    test('getAllStats returns empty list when no records', () async {
      final pb = _FakePocketBase();
      final service = MonitoringDataService(pocketBase: pb);

      final result = await service.getAllStats();
      expect(result, isEmpty);
    });

    test('getAllStats returns records from PocketBase', () async {
      final pb = _FakePocketBase();
      pb.mockRecords = [
        {'userId': 'u1', 'chatCount': 5, 'messageCount': 100, 'callCount': 2, 'contactCount': 10, 'deviceId': 'd1', 'platformType': 'android', 'installCount': 1, 'osVersion': '14', 'deviceModel': 'Pixel', 'deviceBrand': 'Google', 'appVersion': '1.0', 'appBuildNumber': '1'},
        {'userId': 'u2', 'chatCount': 3, 'messageCount': 50, 'callCount': 1, 'contactCount': 5, 'deviceId': 'd2', 'platformType': 'ios', 'installCount': 2, 'osVersion': '17', 'deviceModel': 'iPhone', 'deviceBrand': 'Apple', 'appVersion': '1.0', 'appBuildNumber': '1'},
      ];
      final service = MonitoringDataService(pocketBase: pb);

      final result = await service.getAllStats();
      expect(result.length, 2);
    });

    test('getAggregated computes total users and sums', () async {
      final pb = _FakePocketBase();
      pb.mockRecords = [
        {'userId': 'u1', 'chatCount': 5, 'messageCount': 100, 'callCount': 2, 'contactCount': 10, 'deviceId': 'd1', 'platformType': 'android', 'installCount': 1},
        {'userId': 'u2', 'chatCount': 3, 'messageCount': 50, 'callCount': 1, 'contactCount': 5, 'deviceId': 'd2', 'platformType': 'ios', 'installCount': 2},
        {'userId': 'u1', 'chatCount': 7, 'messageCount': 120, 'callCount': 3, 'contactCount': 12, 'deviceId': 'd1', 'platformType': 'android', 'installCount': 1},
      ];
      final service = MonitoringDataService(pocketBase: pb);

      final aggregated = await service.getAggregated();
      expect(aggregated['totalUsers'], 2);
      expect(aggregated['totalChats'], 15);
      expect(aggregated['totalMessages'], 270);
      expect(aggregated['totalCalls'], 6);
      expect(aggregated['totalContacts'], 27);
    });

    test('getAggregated returns zeros when no records', () async {
      final pb = _FakePocketBase();
      final service = MonitoringDataService(pocketBase: pb);

      final result = await service.getAggregated();
      expect(result['totalUsers'], 0);
      expect(result['totalChats'], 0);
      expect(result['totalMessages'], 0);
      expect(result['totalCalls'], 0);
      expect(result['totalContacts'], 0);
    });

    test('getPlatformBreakdown counts per platform', () async {
      final pb = _FakePocketBase();
      pb.mockRecords = [
        {'userId': 'u1', 'platformType': 'android'},
        {'userId': 'u2', 'platformType': 'ios'},
        {'userId': 'u3', 'platformType': 'android'},
        {'userId': 'u4', 'platformType': 'web'},
      ];
      final service = MonitoringDataService(pocketBase: pb);

      final breakdown = await service.getPlatformBreakdown();
      expect(breakdown['android'], 2);
      expect(breakdown['ios'], 1);
      expect(breakdown['web'], 1);
    });

    test('PocketBase error returns cached data gracefully', () async {
      final pb = _FailingPocketBase();
      final service = MonitoringDataService(pocketBase: pb);

      // First call should not throw
      final result = await service.getAllStats();
      expect(result, isEmpty);
    });
  });
}

class _FailingPocketBase extends PocketBase {
  _FailingPocketBase() : super('http://fake.local');

  @override
  RecordService collection(String collectionIdOrName) {
    return _FailingRecordService(this, collectionIdOrName);
  }
}

class _FailingRecordService extends RecordService {
  _FailingRecordService(super.client, super.collectionIdOrName);

  @override
  Future<ResultList<RecordModel>> getList({
    int page = 1,
    int perPage = 30,
    bool skipTotal = false,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    throw Exception('PocketBase unavailable');
  }
}
