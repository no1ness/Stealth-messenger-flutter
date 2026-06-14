import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/diagnostics/diagnostics_service.dart';
import 'package:stealth/services/diagnostics/service_status.dart';

void main() {
  group('DiagnosticsService.snapshot', () {
    test('collects all 5 sources with happy-path defaults', () async {
      final service = _buildService();
      final result = await service.snapshot();
      final ids = result.map((s) => s.id).toList();
      expect(ids, [
        'attachments',
        'database',
        'identity',
        'p2p',
        'pocketbase',
      ]);
      service.dispose();
    });

    test('database secureStorageReady=false => error', () async {
      final service = _buildService(dashboard: {'secureStorageReady': false});
      final result = await service.snapshot();
      final db = result.firstWhere((s) => s.id == 'database');
      expect(db.state, HealthState.error);
      service.dispose();
    });

    test('attachments throws => error in own slot, others survive',
        () async {
      final service = _buildService(attachmentsThrows: true);
      final result = await service.snapshot();
      final att = result.firstWhere((s) => s.id == 'attachments');
      expect(att.state, HealthState.error);
      // Other sources still ok.
      expect(
        result.firstWhere((s) => s.id == 'database').state,
        HealthState.ok,
      );
      expect(
        result.firstWhere((s) => s.id == 'identity').state,
        HealthState.ok,
      );
      service.dispose();
    });

    test('pocketbase: empty env => error with config message', () async {
      final service = _buildService(pbUrl: null);
      final result = await service.snapshot();
      final pb = result.firstWhere((s) => s.id == 'pocketbase');
      expect(pb.state, HealthState.error);
      expect(pb.detail, contains('not configured'));
      service.dispose();
    });

    test('pocketbase: valid URL => ok with authority', () async {
      final service = _buildService(pbUrl: 'https://pb.example.com:8080/');
      final result = await service.snapshot();
      final pb = result.firstWhere((s) => s.id == 'pocketbase');
      expect(pb.state, HealthState.ok);
      expect(pb.detail, contains('pb.example.com:8080'));
      service.dispose();
    });

    test('p2p retry worker off => warn', () async {
      final service = _buildService(p2pRetry: false, p2pChannels: 2);
      final result = await service.snapshot();
      final p2p = result.firstWhere((s) => s.id == 'p2p');
      expect(p2p.state, HealthState.warn);
      expect(p2p.detail, contains('2 channels'));
      expect(p2p.detail, contains('retry worker off'));
      service.dispose();
    });

    test('identity: null userId => error', () async {
      final service = _buildService(userId: null);
      final result = await service.snapshot();
      final id = result.firstWhere((s) => s.id == 'identity');
      expect(id.state, HealthState.error);
      service.dispose();
    });
  });

  group('DiagnosticsService.watch', () {
    test('emits immediately on listen via onListen callback', () async {
      final service = _buildService();
      final first = await service.watch().first;
      expect(first, hasLength(5));
      expect(service.lastKnownSnapshot, isNotNull);
      service.dispose();
    });

    test('updates lastKnownSnapshot after first emit', () async {
      final service = _buildService();
      expect(service.lastKnownSnapshot, isNull);
      await service.watch().first;
      expect(service.lastKnownSnapshot, isNotNull);
      expect(service.lastKnownSnapshot, hasLength(5));
      service.dispose();
    });

    test('Timer.periodic delivers additional snapshots, dispose halts',
        () {
      fakeAsync((async) {
        var emitCount = 0;
        final service = _buildService(
          pollInterval: const Duration(seconds: 5),
        );
        final sub = service.watch().listen((_) => emitCount++);

        // Flush microtasks for the initial onListen emission.
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));
        expect(emitCount, 1, reason: 'onListen-driven emit');

        async.elapse(const Duration(seconds: 5));
        expect(emitCount, 2, reason: 'first periodic tick');

        async.elapse(const Duration(seconds: 5));
        expect(emitCount, 3, reason: 'second periodic tick');

        service.dispose();
        async.elapse(const Duration(seconds: 30));
        expect(emitCount, 3, reason: 'no emits after dispose');

        sub.cancel();
      });
    });
  });

  group('re-entrance', () {
    test('slow source does not start a parallel collect', () async {
      final completer = Completer<Map<String, dynamic>>();
      var dashboardCalls = 0;

      final service = DiagnosticsService(
        dashboardSummary: () {
          dashboardCalls++;
          return completer.future;
        },
        attachmentDebugSummary: () async => {'fileCount': 0},
        getUserId: () async => 'uid',
        p2pActiveChannelCount: () => 0,
        p2pRetryWorkerRunning: () => true,
        pocketbaseUrl: () => 'https://pb.example.com',
        pollInterval: const Duration(milliseconds: 50),
      );

      final f1 = service.snapshot();
      // Second concurrent call MUST short-circuit (return cached empty).
      final result2 = await service.snapshot();
      expect(result2, const <ServiceStatus>[]);
      expect(dashboardCalls, 1);

      completer.complete({'secureStorageReady': true});
      await f1;
      expect(dashboardCalls, 1);
      service.dispose();
    });
  });
}

DiagnosticsService _buildService({
  Map<String, dynamic> dashboard = const {'secureStorageReady': true},
  Map<String, dynamic> attachments = const {'fileCount': 0},
  String? userId = 'uid-1234',
  int p2pChannels = 0,
  bool p2pRetry = true,
  String? pbUrl = 'https://pb.example.com',
  bool dashboardThrows = false,
  bool attachmentsThrows = false,
  Duration pollInterval = const Duration(seconds: 5),
}) =>
    DiagnosticsService(
      dashboardSummary: () async {
        if (dashboardThrows) throw StateError('db down');
        return dashboard;
      },
      attachmentDebugSummary: () async {
        if (attachmentsThrows) throw StateError('attach down');
        return attachments;
      },
      getUserId: () async => userId,
      p2pActiveChannelCount: () => p2pChannels,
      p2pRetryWorkerRunning: () => p2pRetry,
      pocketbaseUrl: () => pbUrl,
      pollInterval: pollInterval,
    );
