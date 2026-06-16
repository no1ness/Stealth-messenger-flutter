import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/user_directory/presence_service.dart';
import 'package:stealth/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PresenceService setOnline / setOffline', () {
    test('setOnline upserts profile with isOnline=true', () async {
      final h = _Harness.build();
      await h.service.start('user-A');
      await Future<void>.delayed(Duration.zero);

      await h.service.setOnline();

      expect(h.fakeProfiles.lastUpsertBody, isNotNull);
      expect(h.fakeProfiles.lastUpsertBody!['isOnline'], isTrue);
      expect(h.fakeProfiles.lastUpsertBody!['lastSeen'], isNotEmpty);
      await h.dispose();
    });

    test('setOffline upserts profile with isOnline=false', () async {
      final h = _Harness.build();
      await h.service.start('user-A');
      await Future<void>.delayed(Duration.zero);

      await h.service.setOffline();

      expect(h.fakeProfiles.lastUpsertBody, isNotNull);
      expect(h.fakeProfiles.lastUpsertBody!['isOnline'], isFalse);
      await h.dispose();
    });

    test('setOnline starts heartbeat that repeats upsert', () async {
      fakeAsync((async) {
        final h = _Harness.build();
        unawaited(h.service.start('user-A'));
        async.flushMicrotasks();

        unawaited(h.service.setOnline());
        async.flushMicrotasks();

        expect(h.fakeProfiles.upsertCount, 1);

        async.elapse(const Duration(seconds: 30));

        expect(h.fakeProfiles.upsertCount, greaterThanOrEqualTo(2));
        h.disposeSync();
      });
    });
  });

  group('PresenceService heartbeat', () {
    test('startHeartbeat fires every 30 seconds', () async {
      fakeAsync((async) {
        final h = _Harness.build();
        unawaited(h.service.start('user-A'));
        async.flushMicrotasks();

        h.service.startHeartbeat();
        async.flushMicrotasks();

        expect(h.fakeProfiles.upsertCount, 0);

        async.elapse(const Duration(seconds: 30));
        expect(h.fakeProfiles.upsertCount, 1);

        async.elapse(const Duration(seconds: 30));
        expect(h.fakeProfiles.upsertCount, 2);

        h.disposeSync();
      });
    });

    test('stopHeartbeat cancels the timer', () async {
      fakeAsync((async) {
        final h = _Harness.build();
        unawaited(h.service.start('user-A'));
        async.flushMicrotasks();

        h.service.startHeartbeat();
        h.service.stopHeartbeat();

        async.elapse(const Duration(seconds: 60));

        expect(h.fakeProfiles.upsertCount, 0);
        h.disposeSync();
      });
    });
  });

  group('PresenceService onPresenceChange', () {
    test('emits profile when subscription fires', () async {
      final h = _Harness.build();
      await h.service.start('user-A');
      await Future<void>.delayed(Duration.zero);

      final received = <Map<String, dynamic>>[];
      final sub = h.service.onPresenceChange.listen(received.add);

      h.fakeProfiles.fireCallback(
        action: 'create',
        record: _buildPresenceRecord(
          userId: 'user-B', isOnline: true, lastSeen: '2025-01-01T00:00:00Z',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single['userId'], 'user-B');
      expect(received.single['isOnline'], isTrue);

      await sub.cancel();
      await h.dispose();
    });

    test('ignores own userId events', () async {
      final h = _Harness.build();
      await h.service.start('user-A');
      await Future<void>.delayed(Duration.zero);

      final received = <Map<String, dynamic>>[];
      final sub = h.service.onPresenceChange.listen(received.add);

      h.fakeProfiles.fireCallback(
        action: 'update',
        record: _buildPresenceRecord(
          userId: 'user-A', isOnline: true, lastSeen: '2025-01-01T00:00:00Z',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);

      await sub.cancel();
      await h.dispose();
    });

    test('ignores actions other than create/update', () async {
      final h = _Harness.build();
      await h.service.start('user-A');
      await Future<void>.delayed(Duration.zero);

      final received = <Map<String, dynamic>>[];
      final sub = h.service.onPresenceChange.listen(received.add);

      h.fakeProfiles.fireCallback(
        action: 'delete',
        record: _buildPresenceRecord(
          userId: 'user-B', isOnline: false, lastSeen: '',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);

      await sub.cancel();
      await h.dispose();
    });
  });

  group('PresenceService dispose', () {
    test('dispose stops heartbeat and closes stream', () async {
      fakeAsync((async) {
        final h = _Harness.build();
        unawaited(h.service.start('user-A'));
        async.flushMicrotasks();

        h.service.startHeartbeat();
        async.flushMicrotasks();

        unawaited(h.dispose());
        async.elapse(const Duration(seconds: 60));

        expect(h.fakeProfiles.upsertCount, 0);
      });
    });

    test('dispose is idempotent', () async {
      final h = _Harness.build();
      await h.service.start('user-A');
      await Future<void>.delayed(Duration.zero);
      await h.dispose();
      await h.dispose();
    });
  });

  group('PresenceService reconnect', () {
    test('subscribe error triggers backoff reconnect', () async {
      fakeAsync((async) {
        final h = _Harness.build();
        h.fakeProfiles.failNextSubscribe = true;

        unawaited(h.service.start('user-A'));
        async.flushMicrotasks();

        expect(h.fakeProfiles.subscribeCallCount, 1);

        async.elapse(const Duration(seconds: 1));
        expect(h.fakeProfiles.subscribeCallCount, 2);

        h.disposeSync();
      });
    });

    test('connectivity restored triggers immediate reconnect', () async {
      fakeAsync((async) {
        final h = _Harness.build();
        h.fakeProfiles.failNextSubscribe = true;

        unawaited(h.service.start('user-A'));
        async.flushMicrotasks();
        expect(h.fakeProfiles.subscribeCallCount, 1);

        h.fakeProfiles.failNextSubscribe = false;
        h.fakeConnectivity.push([ConnectivityResult.wifi]);

        // Timer(Duration.zero) fires on elapse(Duration.zero)
        async.elapse(Duration.zero);

        expect(h.fakeProfiles.subscribeCallCount, 2);

        h.disposeSync();
      });
    });
  });
}

class _Harness {
  late final _FakePocketBase fakePb;
  late final _FakeProfilesCollection fakeProfiles;
  late final _FakeConnectivity fakeConnectivity;
  late final _FakeAuthStore fakeAuth;
  late final PresenceService service;
  bool _disposed = false;

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
    h.service = PresenceService.test(
      pocketBase: h.fakePb,
      connectivity: h.fakeConnectivity,
      authService: fakeAuthService,
    );
    h.fakePb.installFakeService(h.fakeProfiles);
    return h;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await service.dispose();
    await fakeConnectivity.close();
  }

  void disposeSync() {
    if (_disposed) return;
    _disposed = true;
    service.dispose();
    fakeConnectivity.close();
  }
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

class _FakeProfilesCollection extends RecordService {
  _FakeProfilesCollection(super.client, super.collectionIdOrName);

  Map<String, dynamic>? lastUpsertBody;
  int upsertCount = 0;
  bool failNextSubscribe = false;

  RecordSubscriptionFunc? _callback;
  int subscribeCallCount = 0;
  int unsubscribeCallCount = 0;

  @override
  Future<RecordModel> create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    lastUpsertBody = Map<String, dynamic>.from(body);
    upsertCount += 1;
    return RecordModel({
      'id': 'fake-create-${DateTime.now().microsecondsSinceEpoch}',
      'collectionName': 'user_profiles',
      ...body,
    });
  }

  @override
  Future<RecordModel> update(
    String id, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    lastUpsertBody = Map<String, dynamic>.from(body);
    upsertCount += 1;
    return RecordModel({
      'id': id,
      'collectionName': 'user_profiles',
      ...body,
    });
  }

  @override
  Future<RecordModel> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    String? sort,
  }) async {
    return RecordModel({
      'id': 'existing-profile',
      'collectionName': 'user_profiles',
      'userId': 'user-A',
      'isOnline': true,
      'lastSeen': '2025-01-01T00:00:00Z',
    });
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    String topic,
    RecordSubscriptionFunc callback, {
    String? expand,
    String? filter,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    subscribeCallCount += 1;
    _callback = callback;
    if (failNextSubscribe) {
      failNextSubscribe = false;
      throw ClientException(statusCode: 500, response: {'message': 'timeout'});
    }
    return _unsubscribe;
  }

  Future<void> _unsubscribe() async {
    unsubscribeCallCount += 1;
    _callback = null;
  }

  void fireCallback({
    required String action,
    required RecordModel record,
  }) {
    final cb = _callback;
    if (cb == null) {
      throw StateError('No subscription callback registered');
    }
    cb(RecordSubscriptionEvent(action: action, record: record));
  }
}

class _FakeConnectivity implements Connectivity {
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  void push(List<ConnectivityResult> results) {
    _controller.add(results);
  }

  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
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

RecordModel _buildPresenceRecord({
  required String userId,
  required bool isOnline,
  required String lastSeen,
  String deviceModel = '',
  String platform = '',
  String appVersion = '',
  String publicKey = '',
}) {
  return RecordModel({
    'id': 'rec-${DateTime.now().microsecondsSinceEpoch}',
    'collectionId': 'col_user_profiles',
    'collectionName': 'user_profiles',
    'userId': userId,
    'isOnline': isOnline,
    'lastSeen': lastSeen,
    'deviceModel': deviceModel,
    'platform': platform,
    'appVersion': appVersion,
    'publicKey': publicKey,
  });
}
