import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/incoming_call_service.dart';
import 'package:stealth/services/signaling/pb_user_id.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/storage_service.dart';

/// Smoke test that runs the full signaling flow against a real PocketBase
/// instance.
///
/// The test relies on `WebRtcSignalingService` (and `IncomingCallSignalingService`
/// for the receive-side scenario) to self-register PocketBase users via
/// `PocketBaseAuthService.ensureAuth` — it does NOT pre-provision users
/// itself. This exercises the identity contract introduced in Phase 1 of the
/// post-PocketBase hardening plan:
///
///   PocketBase `users.id` == `pbIdFromLocalUuid(selfUserId)`
///
/// which makes the deployment compatible with strict API rules on the
/// `rtc_signaling` collection (`@request.data.creator = @request.auth.id`).
///
/// Required env:
///   POCKETBASE_TEST_URL  — e.g. http://127.0.0.1:8090
///
/// Optional env (used to delete the throwaway users at the end of the run):
///   POCKETBASE_TEST_ADMIN_EMAIL
///   POCKETBASE_TEST_ADMIN_PASSWORD
///
/// Optional manual step to also validate strict API rules:
///   On the test server, set `rtc_signaling.createRule` to
///   `@request.auth.id != "" && @request.data.creator = @request.auth.id`
///   and re-run this test. It must still pass — the SUT writes
///   `creator = request.auth.id` by construction.
void main() {
  final pbUrl = Platform.environment['POCKETBASE_TEST_URL'];
  if (pbUrl == null || pbUrl.isEmpty) {
    test('PocketBase signaling smoke (skipped: POCKETBASE_TEST_URL not set)',
        () {
      markTestSkipped(
        'Set POCKETBASE_TEST_URL to enable end-to-end signaling smoke test.',
      );
    });
    return;
  }

  test(
    'two services exchange offer/answer/hangup through real PocketBase',
    () async {
      final adminEmail = Platform.environment['POCKETBASE_TEST_ADMIN_EMAIL'];
      final adminPassword =
          Platform.environment['POCKETBASE_TEST_ADMIN_PASSWORD'];

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final userIdA = 'smoke_a_$stamp';
      final userIdB = 'smoke_b_$stamp';
      final roomId = 'smoke_room_$stamp';

      final pbA = PocketBase(pbUrl);
      final pbB = PocketBase(pbUrl);

      WebRtcSignalingService? serviceA;
      WebRtcSignalingService? serviceB;
      String? pbRecIdA;
      String? pbRecIdB;

      try {
        serviceA = WebRtcSignalingService(
          pocketBase: pbA,
          storage: _NoopStorage(),
          connectivity: _SilentConnectivity(),
        );
        serviceB = WebRtcSignalingService(
          pocketBase: pbB,
          storage: _NoopStorage(),
          connectivity: _SilentConnectivity(),
        );

        // Capture B's incoming first so we don't lose the offer.
        final bReceived = <RtcMessage>[];
        final bSub = serviceB.incoming.listen(bReceived.add);

        // The service registers each user with an explicit `id` matching
        // `selfUserId` (no dashes ⇒ already a valid PB id). After connect
        // we verify the round-trip succeeded — this is the identity check
        // that strict API rules will enforce server-side.
        await serviceB.connect(roomId: roomId, selfUserId: userIdB);
        await serviceA.connect(roomId: roomId, selfUserId: userIdA);

        final modelA = pbA.authStore.model;
        final modelB = pbB.authStore.model;
        pbRecIdA = (modelA is RecordModel) ? modelA.id : null;
        pbRecIdB = (modelB is RecordModel) ? modelB.id : null;
        expect(
          pbRecIdA,
          userIdA,
          reason: 'WebRtcSignalingService must register users.id == selfUserId '
              'so that strict createRule (@request.data.creator = @request.auth.id) '
              'accepts the writes.',
        );
        expect(pbRecIdB, userIdB);

        // Allow PocketBase realtime to propagate subscriptions.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        await serviceA.sendOffer(
          roomId: roomId,
          targetUserId: userIdB,
          sdp: const {'type': 'offer', 'sdp': 'v=0\r\nfake-offer\r\n'},
        );

        await _waitFor(
          () => bReceived.any((m) => m.type == RtcMessageType.offer),
          description: 'offer arrives at B',
        );

        // Now A subscribes to its own incoming for the answer.
        final aReceived = <RtcMessage>[];
        final aSub = serviceA.incoming.listen(aReceived.add);

        await serviceB.sendAnswer(
          roomId: roomId,
          targetUserId: userIdA,
          sdp: const {'type': 'answer', 'sdp': 'v=0\r\nfake-answer\r\n'},
        );

        await _waitFor(
          () => aReceived.any((m) => m.type == RtcMessageType.answer),
          description: 'answer arrives at A',
        );

        // Hangup round-trip.
        await serviceA.sendHangup(roomId: roomId, targetUserId: userIdB);
        await _waitFor(
          () => bReceived.any((m) => m.type == RtcMessageType.hangup),
          description: 'hangup arrives at B',
        );

        final offerAtB = bReceived.firstWhere(
          (m) => m.type == RtcMessageType.offer,
        );
        expect(offerAtB.creator, userIdA);
        expect(offerAtB.target, userIdB);
        expect(offerAtB.payload['sdp'], contains('fake-offer'));

        final answerAtA = aReceived.firstWhere(
          (m) => m.type == RtcMessageType.answer,
        );
        expect(answerAtA.creator, userIdB);
        expect(answerAtA.target, userIdA);
        expect(answerAtA.payload['sdp'], contains('fake-answer'));

        await aSub.cancel();
        await bSub.cancel();
      } finally {
        await serviceA?.disconnect();
        await serviceB?.disconnect();
        // Best-effort cleanup of throwaway users (only when admin auth was
        // supplied — otherwise we leave the records and rely on the
        // collection's TTL hook documented in POCKETBASE_SETUP.md).
        if (adminEmail != null && adminPassword != null) {
          await _safeDeleteUser(pbUrl, adminEmail, adminPassword, pbRecIdA);
          await _safeDeleteUser(pbUrl, adminEmail, adminPassword, pbRecIdB);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'IncomingCallSignalingService receives offer for canonical-UUID self id',
    () async {
      // Receive-side scenario for the global incoming-call listener. This
      // covers the regression that motivated the pb-user-id-collision fix:
      //
      //   1. Both peers use canonical UUIDs, so `pbIdFromLocalUuid` takes the
      //      SHA-256[:15] branch (not the non-UUID passthrough exercised by
      //      the test above). This validates that PocketBase accepts a custom
      //      15-char hash id and that strict API rules continue to match.
      //   2. `IncomingCallSignalingService.start()` must call ensureAuth
      //      BEFORE subscribe — otherwise the SSE listRule
      //      (`target = @request.auth.id`) is always false and the callee
      //      never sees the offer. Catching this is the whole point of the
      //      new scenario.
      //   3. The offer payload carries `creatorUuid` (the caller's local
      //      UUID); the resolver hashes known peers so `IncomingCallOffer
      //      .fromUserId` surfaces the local UUID, not the 15-char hash.
      final adminEmail = Platform.environment['POCKETBASE_TEST_ADMIN_EMAIL'];
      final adminPassword =
          Platform.environment['POCKETBASE_TEST_ADMIN_PASSWORD'];

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final callerUuid = _deterministicUuid('caller-$stamp');
      final calleeUuid = _deterministicUuid('callee-$stamp');
      final roomId = 'smoke_room_uuid_$stamp';

      final pbCaller = PocketBase(pbUrl);
      final pbCallee = PocketBase(pbUrl);

      WebRtcSignalingService? caller;
      IncomingCallSignalingService? callee;
      StreamSubscription<IncomingCallEvent>? eventsSub;

      try {
        caller = WebRtcSignalingService(
          pocketBase: pbCaller,
          storage: _NoopStorage(),
          connectivity: _SilentConnectivity(),
        );
        callee = IncomingCallSignalingService(
          pocketBase: pbCallee,
          knownPeerUuidsProvider: () => [callerUuid],
          authService: PocketBaseAuthService(
            pocketBase: pbCallee,
            storage: _NoopStorage(),
          ),
        );

        final events = <IncomingCallEvent>[];
        eventsSub = callee.events.listen(events.add);

        await callee.start(selfUserId: calleeUuid);
        await caller.connect(roomId: roomId, selfUserId: callerUuid);

        // Sanity-check the identity contract under the SHA-256 derivation
        // before sending — if PocketBase substituted a different id, the
        // strict createRule on the server would reject the offer anyway.
        final modelCaller = pbCaller.authStore.model;
        final pbIdCaller = (modelCaller is RecordModel) ? modelCaller.id : null;
        expect(
          pbIdCaller,
          pbIdFromLocalUuid(callerUuid),
          reason:
              'PocketBase must store the caller account under the SHA-256[:15] '
              'id derived from the canonical UUID — otherwise listRule and '
              'createRule diverge from the wire identity.',
        );

        // Allow PocketBase realtime to attach the SSE subscription.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        await caller.sendOffer(
          roomId: roomId,
          targetUserId: calleeUuid,
          sdp: <String, dynamic>{
            'type': 'offer',
            'sdp': 'v=0\r\nfake-offer-uuid\r\n',
            'purpose': 'call',
            'nickname': 'Caller',
            'callType': 'audio',
            // Caller propagates its UUID explicitly — the 15-char hash is
            // one-way, so without this the callee couldn't surface the
            // caller's local UUID for an unknown peer.
            'creatorUuid': callerUuid,
          },
        );

        await _waitFor(
          () => events.whereType<IncomingCallOffer>().isNotEmpty,
          description: 'IncomingCallOffer reaches global listener',
        );

        final offer = events.whereType<IncomingCallOffer>().first;
        expect(offer.roomId, roomId);
        expect(
          offer.fromUserId,
          callerUuid,
          reason: 'fromUserId must surface the resolved local UUID via '
              'creatorUuid payload (the wire `creator` is a 15-char hash).',
        );
        expect(offer.fromNickname, 'Caller');
        expect(offer.isVideoCall, isFalse);
      } finally {
        await eventsSub?.cancel();
        await callee?.stop();
        await caller?.disconnect();
        if (adminEmail != null && adminPassword != null) {
          await _safeDeleteUser(
            pbUrl,
            adminEmail,
            adminPassword,
            pbIdFromLocalUuid(callerUuid),
          );
          await _safeDeleteUser(
            pbUrl,
            adminEmail,
            adminPassword,
            pbIdFromLocalUuid(calleeUuid),
          );
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'IncomingCallSignalingService surfaces cold-cancel hangup with creatorUuid fallback',
    () async {
      // Cold-cancel scenario: caller initiates a call (offer), then hangs up
      // BEFORE the callee opens the call screen — i.e. only the global
      // IncomingCallSignalingService is running on the callee side. The
      // per-call `WebRtcSignalingService` doesn't exist for that room on the
      // callee yet, so the hangup is delivered exclusively through the
      // global listener.
      //
      // This guards the symmetric `creatorUuid` injection in
      // `WebRtcSignalingService._send`: without it the hangup payload would
      // be empty and `IncomingCallHangup.fromUserId` would fall back to the
      // 15-char hash, breaking any UI that compares against local contact
      // UUIDs.
      final adminEmail = Platform.environment['POCKETBASE_TEST_ADMIN_EMAIL'];
      final adminPassword =
          Platform.environment['POCKETBASE_TEST_ADMIN_PASSWORD'];

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final callerUuid = _deterministicUuid('cold-caller-$stamp');
      final calleeUuid = _deterministicUuid('cold-callee-$stamp');
      final roomId = 'smoke_room_cold_$stamp';

      final pbCaller = PocketBase(pbUrl);
      final pbCallee = PocketBase(pbUrl);

      WebRtcSignalingService? caller;
      IncomingCallSignalingService? callee;
      StreamSubscription<IncomingCallEvent>? eventsSub;

      try {
        caller = WebRtcSignalingService(
          pocketBase: pbCaller,
          storage: _NoopStorage(),
          connectivity: _SilentConnectivity(),
        );
        callee = IncomingCallSignalingService(
          pocketBase: pbCallee,
          knownPeerUuidsProvider: () => [callerUuid],
          authService: PocketBaseAuthService(
            pocketBase: pbCallee,
            storage: _NoopStorage(),
          ),
        );

        final events = <IncomingCallEvent>[];
        eventsSub = callee.events.listen(events.add);

        await callee.start(selfUserId: calleeUuid);
        await caller.connect(roomId: roomId, selfUserId: callerUuid);

        // Allow PocketBase realtime to attach the SSE subscription.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        await caller.sendOffer(
          roomId: roomId,
          targetUserId: calleeUuid,
          sdp: <String, dynamic>{
            'type': 'offer',
            'sdp': 'v=0\r\nfake-cold-offer\r\n',
            'purpose': 'call',
            'nickname': 'ColdCaller',
            'callType': 'audio',
          },
        );

        await _waitFor(
          () => events.whereType<IncomingCallOffer>().isNotEmpty,
          description: 'IncomingCallOffer reaches global listener',
        );

        // Caller cancels before callee opens the call screen. Hangup
        // payload is empty at the call site — `_send` is responsible for
        // injecting creatorUuid.
        await caller.sendHangup(roomId: roomId, targetUserId: calleeUuid);

        await _waitFor(
          () => events.whereType<IncomingCallHangup>().isNotEmpty,
          description: 'IncomingCallHangup reaches global listener',
        );

        final hangup = events.whereType<IncomingCallHangup>().first;
        expect(hangup.roomId, roomId);
        expect(
          hangup.fromUserId,
          callerUuid,
          reason:
              'fromUserId must come from payload creatorUuid injected by '
              'WebRtcSignalingService._send, not the 15-char wire hash. '
              'A failure here would mean the centralised injection is missing '
              'and cold-cancel UIs would see an unresolved hash.',
        );
      } finally {
        await eventsSub?.cancel();
        await callee?.stop();
        await caller?.disconnect();
        if (adminEmail != null && adminPassword != null) {
          await _safeDeleteUser(
            pbUrl,
            adminEmail,
            adminPassword,
            pbIdFromLocalUuid(callerUuid),
          );
          await _safeDeleteUser(
            pbUrl,
            adminEmail,
            adminPassword,
            pbIdFromLocalUuid(calleeUuid),
          );
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

/// Produces a deterministic canonical UUID-shaped string from [seed].
///
/// Test fixture only — gives reproducible identifiers in 8-4-4-4-12 hex
/// without depending on a UUID package. The string passes the canonical
/// UUID regex used by `pbIdFromLocalUuid`, so it exercises the SHA-256
/// derivation branch rather than the non-UUID passthrough.
String _deterministicUuid(String seed) {
  final bytes = sha256.convert(utf8.encode('stealth-test-uuid:$seed')).bytes;
  final hex = bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

Future<void> _safeDeleteUser(
  String baseUrl,
  String adminEmail,
  String adminPassword,
  String? id,
) async {
  if (id == null || id.isEmpty) return;
  try {
    final adminPb = PocketBase(baseUrl);
    await adminPb.admins.authWithPassword(adminEmail, adminPassword);
    await adminPb.collection('users').delete(id);
  } catch (_) {
    // best-effort cleanup
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  required String description,
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(step);
  }
  fail('Timed out waiting for: $description');
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

class _SilentConnectivity implements Connectivity {
  final StreamController<List<ConnectivityResult>> _ctrl =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _ctrl.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];
}
