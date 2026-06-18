import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/incoming_call_service.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/storage_service.dart';

void main() {
  group('IncomingCallSignalingService subscription', () {
    late _Harness h;

    setUp(() {
      h = _Harness.build();
    });

    tearDown(() async {
      await h.dispose();
    });

    test('start() subscribes to rtc_signaling collection', () async {
      await h.service.start(selfUserId: 'user-A');
      expect(h.fakeRecordService.subscribeCallCount, 1);
    });

    test('offer event emits IncomingCallOffer', () async {
      await h.service.start(selfUserId: 'user-A');
      final events = <IncomingCallEvent>[];
      h.service.events.listen(events.add);

      h.fakeRecordService.fireCallback(action: 'create', record: _buildRecord(
        id: 'r1',
        roomId: 'room-1',
        creator: 'user-A',
        target: pbIdFromLocalUuid('user-A'),
        type: 'offer',
        payload: {
          'creatorLocalId': 'user-B',
          'targetLocalId': 'user-A',
          'sdp': 'v=0',
          'callType': 'audio',
          'nickname': 'Bob',
        },
      ));

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<IncomingCallOffer>());
      final offer = events.first as IncomingCallOffer;
      expect(offer.roomId, 'room-1');
      expect(offer.fromNickname, 'Bob');
      expect(offer.isVideoCall, false);
      expect(offer.sdp, isNotEmpty);
    });

    test('hangup event emits IncomingCallHangup', () async {
      await h.service.start(selfUserId: 'user-A');
      final events = <IncomingCallEvent>[];
      h.service.events.listen(events.add);

      h.fakeRecordService.fireCallback(action: 'create', record: _buildRecord(
        id: 'r2',
        roomId: 'room-1',
        creator: 'user-B',
        target: pbIdFromLocalUuid('user-A'),
        type: 'hangup',
        payload: {
          'creatorLocalId': 'user-B',
          'targetLocalId': 'user-A',
        },
      ));

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<IncomingCallHangup>());
      final hangup = events.first as IncomingCallHangup;
      expect(hangup.roomId, 'room-1');
    });

    test('events with target != selfUserId are ignored', () async {
      await h.service.start(selfUserId: 'user-A');
      final events = <IncomingCallEvent>[];
      h.service.events.listen(events.add);

      // Event targeting different user
      h.fakeRecordService.fireCallback(action: 'create', record: _buildRecord(
        id: 'r3',
        roomId: 'room-1',
        creator: 'user-C',
        target: pbIdFromLocalUuid('user-B'), // not self
        type: 'offer',
        payload: {
          'creatorLocalId': 'user-C',
          'targetLocalId': 'user-A',
          'sdp': 'v=0',
        },
      ));

      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('declineCall creates hangup record in PB', () async {
      await h.service.start(selfUserId: 'user-A');

      await h.service.declineCall(
        roomId: 'room-1',
        callerUserId: 'user-B',
        selfUserId: 'user-A',
      );

      expect(h.fakeRecordService.lastCreateBody, isNotNull);
      expect(h.fakeRecordService.lastCreateBody!['roomId'], 'room-1');
      expect(h.fakeRecordService.lastCreateBody!['type'], 'hangup');
      expect(h.fakeRecordService.lastCreateBody!['payload']['creatorLocalId'], 'user-A');
      expect(h.fakeRecordService.lastCreateBody!['payload']['targetLocalId'], 'user-B');
    });

    test('stop() unsubscribes', () async {
      await h.service.start(selfUserId: 'user-A');
      expect(h.fakeRecordService.subscribeCallCount, 1);

      await h.service.stop();
      expect(h.fakeRecordService.unsubscribeCallCount, 1);
    });
  });
}

class _Harness {
  _Harness._({
    required this.fakePb,
    required this.fakeRecordService,
    required this.service,
  });

  final _FakePocketBase fakePb;
  final _FakeRecordService fakeRecordService;
  final IncomingCallSignalingService service;

  static _Harness build() {
    final fakePb = _FakePocketBase();
    final fakeRecordService = _FakeRecordService(fakePb, 'rtc_signaling');
    fakePb.installFakeService(fakeRecordService);

    final service = IncomingCallSignalingService(
      pocketBase: fakePb,
      storage: _NoopStorage(),
    );

    return _Harness._(
      fakePb: fakePb,
      fakeRecordService: fakeRecordService,
      service: service,
    );
  }

  Future<void> dispose() async {
    await service.stop();
  }
}

class _FakePocketBase extends PocketBase {
  _FakePocketBase()
      : super('http://fake.local', authStore: _FakeAuthStore());

  RecordService? _installed;

  void installFakeService(RecordService service) {
    _installed = service;
  }

  @override
  RecordService collection(String collectionIdOrName) {
    if (_installed != null && collectionIdOrName == 'rtc_signaling') {
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

class _FakeRecordService extends RecordService {
  _FakeRecordService(super.client, super.collectionIdOrName);

  Map<String, dynamic>? lastCreateBody;
  int subscribeCallCount = 0;
  int unsubscribeCallCount = 0;
  RecordSubscriptionFunc? _callback;

  @override
  Future<RecordModel> create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<dynamic> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    lastCreateBody = Map<String, dynamic>.from(body);
    return RecordModel({
      'id': 'fake-${DateTime.now().microsecondsSinceEpoch}',
      'collectionName': 'rtc_signaling',
      ...Map<String, dynamic>.from(body),
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

RecordModel _buildRecord({
  required String id,
  required String roomId,
  required String creator,
  required String target,
  required String type,
  required Map<String, dynamic> payload,
}) {
  return RecordModel({
    'id': id,
    'created': DateTime.now().toUtc().toIso8601String(),
    'collectionId': 'col_rtc',
    'collectionName': 'rtc_signaling',
    'roomId': roomId,
    'creator': creator,
    'target': target,
    'type': type,
    'payload': payload,
  });
}
