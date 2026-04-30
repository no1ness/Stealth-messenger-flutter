import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/services/signaling/rtc_message.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/storage_service.dart';

/// Smoke test that runs the full signaling flow against a real PocketBase
/// instance.
///
/// Modeled after `client/test/message_flow_smoke_test.dart`:
/// reads connection details from environment variables and skips when the
/// backend is not configured. Requires a PocketBase server with the
/// `rtc_signaling` collection (see `docs/POCKETBASE_SETUP.md`) — without it
/// the test is silently skipped so that the regular `flutter test` run stays
/// green.
///
/// Required env:
///   POCKETBASE_TEST_URL  — e.g. http://127.0.0.1:8090
///
/// Optional env (admin endpoints used to provision throwaway users):
///   POCKETBASE_TEST_ADMIN_EMAIL
///   POCKETBASE_TEST_ADMIN_PASSWORD
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

      _TestUser? userA;
      _TestUser? userB;
      WebRtcSignalingService? serviceA;
      WebRtcSignalingService? serviceB;

      try {
        userA = await _provisionUser(
          pbA,
          adminEmail: adminEmail,
          adminPassword: adminPassword,
          localId: userIdA,
        );
        userB = await _provisionUser(
          pbB,
          adminEmail: adminEmail,
          adminPassword: adminPassword,
          localId: userIdB,
        );

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

        // Capture B's incoming messages first so we don't lose the offer.
        final bReceived = <RtcMessage>[];
        final bSub = serviceB.incoming.listen(bReceived.add);

        await serviceB.connect(roomId: roomId, selfUserId: userIdB);
        await serviceA.connect(roomId: roomId, selfUserId: userIdA);

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
        // Best-effort cleanup of provisioned users (only when admin auth was
        // supplied — otherwise we leave the records and rely on the
        // collection's TTL hook documented in POCKETBASE_SETUP.md).
        if (adminEmail != null && adminPassword != null) {
          await _safeDeleteUser(pbUrl, adminEmail, adminPassword, userA?.id);
          await _safeDeleteUser(pbUrl, adminEmail, adminPassword, userB?.id);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _TestUser {
  _TestUser({required this.id, required this.email, required this.password});
  final String id;
  final String email;
  final String password;
}

Future<_TestUser> _provisionUser(
  PocketBase pb, {
  required String? adminEmail,
  required String? adminPassword,
  required String localId,
}) async {
  final email = '$localId@stealth.local';
  final password = _randomPassword();

  // Ensure the user exists. With admin credentials we can be authoritative;
  // otherwise we fall back to plain create (works only if the collection
  // allows unauthenticated `users.create`).
  if (adminEmail != null && adminPassword != null) {
    final adminPb = PocketBase(pb.baseUrl);
    await adminPb.admins.authWithPassword(adminEmail, adminPassword);
    try {
      await adminPb.collection('users').create(body: {
        'email': email,
        'password': password,
        'passwordConfirm': password,
        'name': localId,
      });
    } on ClientException catch (_) {
      // Already exists from a previous run: ignore and reuse.
    }
  } else {
    try {
      await pb.collection('users').create(body: {
        'email': email,
        'password': password,
        'passwordConfirm': password,
        'name': localId,
      });
    } on ClientException catch (_) {
      // ignore — assume password from a previous run; we'll fail fast on auth.
    }
  }

  final auth = await pb.collection('users').authWithPassword(email, password);
  return _TestUser(id: auth.record!.id, email: email, password: password);
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

String _randomPassword() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final rand = math.Random.secure();
  return List<String>.generate(
    24,
    (_) => alphabet[rand.nextInt(alphabet.length)],
  ).join();
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
