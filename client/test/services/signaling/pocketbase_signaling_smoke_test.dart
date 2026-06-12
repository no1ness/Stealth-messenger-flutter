import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/storage_service.dart';

/// Smoke test that runs the full signaling flow against a real PocketBase
/// instance.
///
/// The test relies on `WebRtcSignalingService` to self-register PocketBase
/// users via `_ensureAuth` — it does NOT pre-provision users itself. This
/// exercises the identity contract introduced in Phase 1 of the
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

      final stamp = DateTime.now().microsecondsSinceEpoch % 100000;
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

        pbRecIdA = pbA.authStore.record?.id;
        pbRecIdB = pbB.authStore.record?.id;
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
    await adminPb
        .collection('_superusers')
        .authWithPassword(adminEmail, adminPassword);
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
