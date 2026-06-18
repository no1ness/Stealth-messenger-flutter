import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/user_directory/presence_service.dart';
import 'package:stealth/services/user_directory/user_directory_service.dart';
import 'package:stealth/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserDirectoryService fetchAllProfiles', () {
    test('returns parsed profiles from PocketBase', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [
        RecordModel({
          'id': 'r1',
          'collectionName': 'user_profiles',
          'userId': 'user-A',
          'publicKey': 'pk-a',
          'deviceModel': 'iPhone',
          'platform': 'iOS',
          'appVersion': '1.0.0',
          'registeredAt': '2025-01-01T00:00:00Z',
          'isOnline': true,
          'lastSeen': '2025-01-02T00:00:00Z',
        }),
        RecordModel({
          'id': 'r2',
          'collectionName': 'user_profiles',
          'userId': 'user-B',
          'publicKey': 'pk-b',
          'deviceModel': 'Pixel',
          'platform': 'Android',
          'appVersion': '1.0.1',
          'registeredAt': '2025-01-03T00:00:00Z',
          'isOnline': false,
          'lastSeen': '2025-01-04T00:00:00Z',
        }),
      ];

      final profiles = await h.service.fetchAllProfiles('user-A');

      expect(profiles, hasLength(2));
      expect(profiles[0]['userId'], 'user-A');
      expect(profiles[0]['publicKey'], 'pk-a');
      expect(profiles[0]['isOnline'], isTrue);
      expect(profiles[1]['userId'], 'user-B');
      expect(profiles[1]['platform'], 'Android');
      expect(profiles[1]['isOnline'], isFalse);
    });

    test('returns empty list when PocketBase errors', () async {
      final h = _Harness.build();
      h.fakeProfiles.failNextList = true;

      final profiles = await h.service.fetchAllProfiles('user-A');

      expect(profiles, isEmpty);
    });

    test('caches fetched profiles', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [
        RecordModel({
          'id': 'r1',
          'collectionName': 'user_profiles',
          'userId': 'user-C',
          'isOnline': true,
          'lastSeen': '',
        }),
      ];

      await h.service.fetchAllProfiles('user-A');

      final cached = h.service.getCachedProfiles();
      expect(cached, hasLength(1));
      expect(cached.single['userId'], 'user-C');
    });
  });

  group('UserDirectoryService getCachedProfiles', () {
    test('returns empty when no profiles fetched', () {
      final h = _Harness.build();
      expect(h.service.getCachedProfiles(), isEmpty);
    });

    test('returns a copy (defensive)', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [
        RecordModel({
          'id': 'r1',
          'collectionName': 'user_profiles',
          'userId': 'user-A',
          'isOnline': true,
          'lastSeen': '',
        }),
      ];

      await h.service.fetchAllProfiles('user-A');

      final cached = h.service.getCachedProfiles();
      cached.clear();

      expect(h.service.getCachedProfiles(), hasLength(1));
    });
  });

  group('UserDirectoryService edge cases', () {
    test('handles null and empty fields without crash', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [
        RecordModel({
          'id': 'r4',
          'collectionName': 'user_profiles',
          'userId': 'user-D',
          'publicKey': null,
          'deviceModel': '',
          'platform': null,
          'appVersion': '',
          'registeredAt': null,
          'isOnline': null,
          'lastSeen': null,
        }),
      ];

      final profiles = await h.service.fetchAllProfiles('user-A');
      expect(profiles, hasLength(1));
      expect(profiles[0]['userId'], 'user-D');
      expect(profiles[0]['publicKey'], isEmpty);
      expect(profiles[0]['deviceModel'], '');
    });

    test('handles incomplete schema (missing fields) without error', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [
        RecordModel({
          'id': 'r5',
          'collectionName': 'user_profiles',
          'userId': 'user-E',
          // missing: publicKey, deviceModel, platform, appVersion, etc.
        }),
      ];

      final profiles = await h.service.fetchAllProfiles('user-A');
      expect(profiles, hasLength(1));
      expect(profiles[0]['userId'], 'user-E');
    });

    test('handles non-bool isOnline without crash', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [
        RecordModel({
          'id': 'r6',
          'collectionName': 'user_profiles',
          'userId': 'user-F',
          'publicKey': 'pk-f',
          'isOnline': 'yes', // string instead of bool
          'lastSeen': '2025-01-05T00:00:00Z',
        }),
        RecordModel({
          'id': 'r7',
          'collectionName': 'user_profiles',
          'userId': 'user-G',
          'publicKey': 'pk-g',
          'isOnline': 42, // int instead of bool
          'lastSeen': '2025-01-06T00:00:00Z',
        }),
      ];

      final profiles = await h.service.fetchAllProfiles('user-A');
      expect(profiles, hasLength(2));
      // Should not throw — callers must handle type coercion.
    });

    test('returns empty list when PocketBase returns empty items', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [];

      final profiles = await h.service.fetchAllProfiles('user-A');
      expect(profiles, isEmpty);
    });
  });

  group('UserDirectoryService clearCache', () {
    test('clears cached profiles', () async {
      final h = _Harness.build();
      h.fakeProfiles.items = [
        RecordModel({
          'id': 'r1',
          'collectionName': 'user_profiles',
          'userId': 'user-A',
          'isOnline': true,
          'lastSeen': '',
        }),
      ];

      await h.service.fetchAllProfiles('user-A');
      expect(h.service.getCachedProfiles(), isNotEmpty);

      h.service.clearCache();

      expect(h.service.getCachedProfiles(), isEmpty);
    });
  });
}

class _Harness {
  late final _FakePocketBase fakePb;
  late final _FakeProfilesCollection fakeProfiles;
  late final _FakeAuthStore fakeAuth;
  late final _FakeConnectivity fakeConnectivity;
  late final UserDirectoryService service;

  _Harness._();

  static _Harness build() {
    final h = _Harness._();
    h.fakeAuth = _FakeAuthStore();
    h.fakePb = _FakePocketBase(authStore: h.fakeAuth);
    h.fakeProfiles = _FakeProfilesCollection(h.fakePb, 'user_profiles');
    h.fakeConnectivity = _FakeConnectivity();
    final fakeAuthService = PocketBaseAuthService(
      pocketBase: h.fakePb,
      storage: _NoopStorage(),
    );
    final fakePresence = PresenceService.test(
      pocketBase: h.fakePb,
      connectivity: h.fakeConnectivity,
      authService: fakeAuthService,
    );
    h.service = UserDirectoryService.test(
      pocketBase: h.fakePb,
      authService: fakeAuthService,
      presenceService: fakePresence,
    );
    h.fakePb.installFakeService(h.fakeProfiles);
    return h;
  }

  Future<void> dispose() async {}
}

class _FakeConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];
}

class _FakePocketBase extends PocketBase {
  _FakePocketBase({AuthStore? authStore})
      : super('http://fake.local', authStore: authStore ?? _FakeAuthStore());

  RecordService? _installed;

  void installFakeService(RecordService service) {
    _installed = service;
  }

  @override
  RecordService collection(String collectionIdOrName) {
    if (_installed != null && collectionIdOrName == 'user_profiles') {
      return _installed!;
    }
    return super.collection(collectionIdOrName);
  }
}

class _FakeAuthStore extends AuthStore {
  @override
  bool get isValid => true;

  @override
  RecordModel? get record => RecordModel({
        'id': 'user-A',
        'collectionId': 'users',
        'collectionName': 'users',
      });
}

class _NoopStorage implements StorageService {
  @override
  Future<void> init() async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> deleteAll() async {}
}

class _FakeProfilesCollection extends RecordService {
  _FakeProfilesCollection(super.client, super.collectionIdOrName);

  List<RecordModel> items = [];
  bool failNextList = false;

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
    if (failNextList) {
      failNextList = false;
      throw ClientException(statusCode: 500, response: {'message': 'boom'});
    }
    return ResultList<RecordModel>(
      page: page,
      perPage: perPage,
      totalItems: items.length,
      totalPages: 1,
      items: items,
    );
  }
}
