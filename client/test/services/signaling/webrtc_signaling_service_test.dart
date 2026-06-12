import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/signaling_transport.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/storage_service.dart';

/// Manual-fake unit tests for WebRtcSignalingService.
///
/// Style follows the project convention (see widgets/contacts_screen_semantics_test.dart):
/// no mockito/mocktail, just hand-written `class _FakeX extends|implements Y`.

void main() {
  group('WebRtcSignalingService send methods', () {
    late _Harness h;

    setUp(() async {
      h = await _Harness.connected();
    });

    tearDown(() async {
      await h.dispose();
    });

    test('sendOffer creates record with correct body', () async {
      await h.service.sendOffer(
        roomId: 'room-1',
        targetUserId: 'user-B',
        sdp: {'type': 'offer', 'sdp': 'v=0\r\n'},
      );

      expect(h.fakeRecordService.lastCreateBody, isNotNull);
      final body = h.fakeRecordService.lastCreateBody!;
      expect(body['roomId'], 'room-1');
      expect(body['creator'], 'user-A');
      expect(body['target'], 'user-B');
      expect(body['type'], 'offer');
      expect(body['payload'], isA<Map<String, dynamic>>());
      expect(body['payload']['sdp'], startsWith('v=0'));
      expect(body['payload']['creatorLocalId'], 'user-A');
      expect(body['payload']['targetLocalId'], 'user-B');
    });

    test('sendAnswer creates record with type=answer', () async {
      await h.service.sendAnswer(
        roomId: 'room-1',
        targetUserId: 'user-B',
        sdp: {'type': 'answer', 'sdp': 'v=0\r\nanswer'},
      );

      expect(h.fakeRecordService.lastCreateBody!['type'], 'answer');
      expect(h.fakeRecordService.lastCreateBody!['payload']['sdp'],
          contains('answer'));
    });

    test('sendCandidate creates record with type=candidate', () async {
      await h.service.sendCandidate(
        roomId: 'room-1',
        targetUserId: 'user-B',
        candidate: {
          'candidate': 'candidate:foo bar 1 udp 12345',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      );

      final body = h.fakeRecordService.lastCreateBody!;
      expect(body['type'], 'candidate');
      expect(body['payload']['candidate'], startsWith('candidate:'));
    });

    test('sendHangup creates record with reason payload', () async {
      await h.service.sendHangup(
        roomId: 'room-1',
        targetUserId: 'user-B',
      );

      final body = h.fakeRecordService.lastCreateBody!;
      expect(body['type'], 'hangup');
      expect(body['payload']['reason'], 'hangup');
      expect(body['payload']['creatorLocalId'], 'user-A');
      expect(body['payload']['targetLocalId'], 'user-B');
    });

    test('rethrows when create() fails', () async {
      h.fakeRecordService.failNextCreateWith =
          ClientException(statusCode: 500, response: {'message': 'boom'});

      expect(
        () => h.service.sendOffer(
          roomId: 'room-1',
          targetUserId: 'user-B',
          sdp: const {'type': 'offer', 'sdp': ''},
        ),
        throwsA(isA<ClientException>()),
      );
    });
  });

  group('WebRtcSignalingService send before connect', () {
    test('sendOffer throws StateError when connect was not called', () async {
      final fakePb = _FakePocketBase();
      final service = WebRtcSignalingService(
        pocketBase: fakePb,
        storage: _NoopStorage(),
        connectivity: _FakeConnectivity(),
      );

      expect(
        () => service.sendOffer(
          roomId: 'room-1',
          targetUserId: 'user-B',
          sdp: const {'type': 'offer', 'sdp': ''},
        ),
        throwsStateError,
      );

      // No connect → no streams subscribed → safe direct dispose paths.
      // Avoid touching disconnect (it would close uninitialised resources fine,
      // but the test purpose is the StateError above).
    });
  });

  group('WebRtcSignalingService incoming stream', () {
    late _Harness h;

    setUp(() async {
      h = await _Harness.connected();
    });

    tearDown(() async {
      await h.dispose();
    });

    test('emits RtcMessage when subscription callback fires for "create"',
        () async {
      final received = <RtcMessage>[];
      final sub = h.service.incoming.listen(received.add);

      h.fakeRecordService.fireCallback(
        action: 'create',
        record: _buildRecord(
          id: 'r1',
          roomId: 'room-1',
          creator: 'user-B',
          target: 'user-A',
          type: 'offer',
          payload: {
            'sdp': 'v=0\r\n',
            'creatorLocalId': 'user-B',
            'targetLocalId': 'user-A',
          },
        ),
      );

      // Allow the broadcast controller to deliver.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.type, RtcMessageType.offer);
      expect(received.single.creator, 'user-B');
      expect(received.single.payload['sdp'], 'v=0\r\n');

      await sub.cancel();
    });

    test('ignores subscription events with action != "create"', () async {
      final received = <RtcMessage>[];
      final sub = h.service.incoming.listen(received.add);

      h.fakeRecordService.fireCallback(
        action: 'update',
        record: _buildRecord(
          id: 'r1',
          roomId: 'room-1',
          creator: 'user-B',
          target: 'user-A',
          type: 'answer',
          payload: const {},
        ),
      );
      h.fakeRecordService.fireCallback(
        action: 'delete',
        record: _buildRecord(
          id: 'r1',
          roomId: 'room-1',
          creator: 'user-B',
          target: 'user-A',
          type: 'hangup',
          payload: const {},
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });

    test('does not crash when record has malformed type field', () async {
      final received = <RtcMessage>[];
      final sub = h.service.incoming.listen(received.add);

      h.fakeRecordService.fireCallback(
        action: 'create',
        record: _buildRecord(
          id: 'bad',
          roomId: 'room-1',
          creator: 'user-B',
          target: 'user-A',
          type: 'bogus',
          payload: const {},
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });
  });

  group('WebRtcSignalingService connectionState', () {
    test('emits connected after subscribe succeeds', () async {
      final h = await _Harness.connected(captureStates: true);

      expect(h.observedStates, contains(SignalingConnectionState.connected));
      await h.dispose();
    });

    test('emits reconnecting → connected when connectivity returns', () async {
      fakeAsync((async) {
        late _Harness h;
        h = _Harness.connectedSync(captureStates: true, async: async);

        h.observedStates.clear();
        h.fakeConnectivity.push([ConnectivityResult.wifi]);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));

        expect(
            h.observedStates, contains(SignalingConnectionState.reconnecting));
        expect(h.observedStates, contains(SignalingConnectionState.connected));

        h.disposeSync(async);
      });
    });

    test('emits disconnected when network is lost', () async {
      final h = await _Harness.connected(captureStates: true);

      h.observedStates.clear();
      h.fakeConnectivity.push([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(h.observedStates, contains(SignalingConnectionState.disconnected));
      await h.dispose();
    });
  });

  group('WebRtcSignalingService disconnect', () {
    test('closes streams and unsubscribes', () async {
      final h = await _Harness.connected();
      final unsubBefore = h.fakeRecordService.unsubscribeCallCount;

      await h.service.disconnect();

      expect(h.fakeRecordService.unsubscribeCallCount, unsubBefore + 1);

      // Subsequent listens to the broadcast streams complete immediately.
      expect(
        h.service.incoming.toList(),
        completes,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

class _Harness {
  _Harness._({
    required this.fakePb,
    required this.fakeRecordService,
    required this.fakeConnectivity,
    required this.service,
    required this.observedStates,
    this.stateSubscription,
  });

  final _FakePocketBase fakePb;
  final _FakeRecordService fakeRecordService;
  final _FakeConnectivity fakeConnectivity;
  final WebRtcSignalingService service;
  final List<SignalingConnectionState> observedStates;
  StreamSubscription<SignalingConnectionState>? stateSubscription;

  static Future<_Harness> connected({bool captureStates = false}) async {
    final h = _build(captureStates: captureStates);
    await h.service.connect(roomId: 'room-1', selfUserId: 'user-A');
    // Drain microtasks so that the initial 'connected' state is observed.
    await Future<void>.delayed(Duration.zero);
    return h;
  }

  static _Harness connectedSync({
    required bool captureStates,
    required FakeAsync async,
  }) {
    final h = _build(captureStates: captureStates);
    h.service.connect(roomId: 'room-1', selfUserId: 'user-A');
    async.flushMicrotasks();
    return h;
  }

  static _Harness _build({required bool captureStates}) {
    final fakeAuth = _FakeAuthStore();
    final fakePb = _FakePocketBase(authStore: fakeAuth);
    // Replace the cached real RecordService with our fake.
    final fakeService = _FakeRecordService(fakePb, 'rtc_signaling');
    fakePb.installFakeService(fakeService);

    final fakeConnectivity = _FakeConnectivity();

    final service = WebRtcSignalingService(
      pocketBase: fakePb,
      storage: _NoopStorage(),
      connectivity: fakeConnectivity,
    );

    final observed = <SignalingConnectionState>[];
    StreamSubscription<SignalingConnectionState>? sub;
    if (captureStates) {
      sub = service.connectionState.listen(observed.add);
    }

    return _Harness._(
      fakePb: fakePb,
      fakeRecordService: fakeService,
      fakeConnectivity: fakeConnectivity,
      service: service,
      observedStates: observed,
      stateSubscription: sub,
    );
  }

  Future<void> dispose() async {
    await stateSubscription?.cancel();
    if (!service.disposed) {
      await service.disconnect();
    }
    await fakeConnectivity.close();
  }

  void disposeSync(FakeAsync async) {
    stateSubscription?.cancel();
    if (!service.disposed) {
      service.disconnect();
      async.flushMicrotasks();
    }
    fakeConnectivity.close();
  }
}

extension on WebRtcSignalingService {
  // Simple disposed probe so that the harness can avoid double-disconnect.
  // The service does not expose a public flag, so we approximate it by
  // attempting a no-op listen and seeing whether the broadcast stream is
  // already closed. We use a try/catch instead of mutation.
  bool get disposed {
    try {
      // ignore: cancel_subscriptions
      final s = incoming.listen((_) {});
      // If the stream is already closed, listen returns a "done" subscription
      // synchronously; we can't observe it here, but we can detect closure via
      // a guarded await on done() in a microtask. For simplicity in tests,
      // assume not-disposed and let dispose() be idempotent.
      s.cancel();
      return false;
    } catch (_) {
      return true;
    }
  }
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakePocketBase extends PocketBase {
  _FakePocketBase({AuthStore? authStore})
      : super('http://fake.local', authStore: authStore ?? _FakeAuthStore());

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

  // Provide a RecordModel matching the harness selfUserId ('user-A') so the
  // identity check inside `_ensureAuth` early-returns (avoiding any network
  // attempt to the fake users collection). The harness wires selfUserId
  // verbatim, so the value is hardcoded here for the same reason.
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
  Object? failNextCreateWith;

  RecordSubscriptionFunc? _callback;
  String? lastFilter;
  int subscribeCallCount = 0;
  int unsubscribeCallCount = 0;

  @override
  Future<RecordModel> create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<dynamic> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    if (failNextCreateWith != null) {
      final err = failNextCreateWith!;
      failNextCreateWith = null;
      throw err;
    }
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
    lastFilter = filter;
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
