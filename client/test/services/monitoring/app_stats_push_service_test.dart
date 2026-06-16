import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/monitoring/app_stats_push_service.dart';

void main() {
  group('AppStatsPushService', () {
    Future<Map<String, dynamic>> _mockStats() async => {
          'userId': 'test-user',
          'deviceId': 'test-device',
          'platformType': 'android',
          'osVersion': '14',
          'deviceModel': 'Pixel',
          'deviceBrand': 'Google',
          'appVersion': '1.0',
          'appBuildNumber': '1',
          'chatCount': 42,
          'messageCount': 1000,
          'callCount': 10,
          'contactCount': 25,
          'installCount': 3,
          'localMediaReady': true,
          'bucketReady': true,
          'secureStorageReady': true,
        };

    test('pushStats calls PocketBase create with correct fields', () async {
      final pb = _FakePocketBase();
      final service = AppStatsPushService(
        pocketBase: pb,
        statsProvider: _mockStats,
      );

      await service.pushStats();

      expect(pb.createCalled, isTrue);
      expect(pb.lastCreatedBody, isNotNull);
      expect(pb.lastCreatedBody!['chatCount'], 42);
      expect(pb.lastCreatedBody!['messageCount'], 1000);
      expect(pb.lastCreatedBody!['callCount'], 10);
      expect(pb.lastCreatedBody!['contactCount'], 25);
      expect(pb.lastCreatedBody!['installCount'], 3);
      expect(pb.lastCreatedBody!['deviceId'], 'test-device');
      expect(pb.lastCreatedBody!['userId'], 'test-user');
    });

    test('pushStats includes all required fields', () async {
      final pb = _FakePocketBase();
      final service = AppStatsPushService(
        pocketBase: pb,
        statsProvider: _mockStats,
      );

      await service.pushStats();

      final requiredFields = [
        'userId', 'deviceId', 'platformType', 'osVersion',
        'deviceModel', 'deviceBrand', 'appVersion', 'appBuildNumber',
        'chatCount', 'contactCount', 'messageCount', 'callCount',
        'installCount',
      ];
      for (final field in requiredFields) {
        expect(pb.lastCreatedBody!.containsKey(field), isTrue,
            reason: 'Missing field: $field');
      }
    });

    test('pushStats does not throw on PocketBase error', () async {
      final errorPb = _FailingPocketBase();
      final service = AppStatsPushService(
        pocketBase: errorPb,
        statsProvider: _mockStats,
      );

      await service.pushStats();
    });

    test('pushStats does not throw on stats provider error', () async {
      final pb = _FakePocketBase();
      final service = AppStatsPushService(
        pocketBase: pb,
        statsProvider: () async => throw Exception('Stats unavailable'),
      );

      await service.pushStats();
      expect(pb.createCalled, isFalse);
    });
  });
}

class _FakePocketBase extends PocketBase {
  _FakePocketBase() : super('http://fake.local');

  bool createCalled = false;
  Map<String, dynamic>? lastCreatedBody;

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
  Future<RecordModel> create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    _pb.createCalled = true;
    _pb.lastCreatedBody = body;
    return RecordModel(body);
  }
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
  Future<RecordModel> create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    throw Exception('PocketBase unavailable');
  }
}
