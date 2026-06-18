import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/services/calls/call_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Clean any leftover test DB from previous runs.
    try {
      final dir = Directory('/tmp/stealth_test');
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Non-critical cleanup; ignore if directory is locked.
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return '/tmp/stealth_test';
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel('plugins.koji-1009.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') return null;
        if (call.method == 'write') return null;
        if (call.method == 'deleteAll') return null;
        return null;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel('plugins.koji-1009.com/flutter_secure_storage'),
      null,
    );
  });

  group('CallHistoryService', () {
    late _Harness h;

    setUp(() async {
      h = _Harness();
      // Ensure clean state before each test.
      await h.cleanCalls();
    });

    tearDown(() async {
      await h.cleanCalls();
    });

    test('recordIncomingCall saves record with correct fields', () async {
      await h.service.recordIncomingCall(
        chatId: 'chat-1',
        fromUserId: 'user-B',
        fromNickname: 'Bob',
      );

      final calls = await h.service.getRecentCallHistory(limit: 10);
      expect(calls, hasLength(1));
      expect(calls.first['chat_id'], 'chat-1');
      expect(calls.first['direction'], 'incoming');
      expect(calls.first['status'], 'initiated');
      expect(calls.first['peer_user_id'], 'user-B');
      expect(calls.first['peer_nickname'], 'Bob');
      expect(calls.first['id'], isNotEmpty);
      expect(calls.first['started_at'], isNotEmpty);
    });

    test('markIncomingCallDeclined updates status', () async {
      await h.service.markIncomingCallDeclined(
        chatId: 'chat-1',
        fromUserId: 'user-B',
      );

      final calls = await h.service.getRecentCallHistory(limit: 10);
      expect(calls, hasLength(1));
      expect(calls.first['chat_id'], 'chat-1');
      expect(calls.first['direction'], 'incoming');
      expect(calls.first['status'], 'declined');
      expect(calls.first['peer_user_id'], 'user-B');
    });

    test('markCurrentUserCallEnded creates record with direction=local',
        () async {
      await h.service.markCurrentUserCallEnded(chatId: 'chat-1');

      final calls = await h.service.getRecentCallHistory(limit: 10);
      expect(calls, hasLength(1));
      expect(calls.first['chat_id'], 'chat-1');
      expect(calls.first['direction'], 'local');
      expect(calls.first['status'], 'ended');
    });

    test('getRecentCallHistory returns limited sorted list', () async {
      // Create three calls in order.
      await h.service.recordIncomingCall(
          chatId: 'chat-1', fromUserId: 'user-B', fromNickname: 'Bob');
      await Future<void>.delayed(Duration.zero);
      await h.service.recordIncomingCall(
          chatId: 'chat-2', fromUserId: 'user-C', fromNickname: 'Carol');
      await Future<void>.delayed(Duration.zero);
      await h.service.markIncomingCallDeclined(
          chatId: 'chat-3', fromUserId: 'user-D');

      final all = await h.service.getRecentCallHistory(limit: 10);
      expect(all, hasLength(3));
      // Most recent first.
      expect(all[0]['chat_id'], 'chat-3');
      expect(all[1]['chat_id'], 'chat-2');
      expect(all[2]['chat_id'], 'chat-1');

      final limited = await h.service.getRecentCallHistory(limit: 2);
      expect(limited, hasLength(2));
      expect(limited[0]['chat_id'], 'chat-3');
      expect(limited[1]['chat_id'], 'chat-2');
    });

    test('empty history returns empty list', () async {
      final calls = await h.service.getRecentCallHistory();
      expect(calls, isEmpty);
    });
  });
}

class _Harness {
  _Harness()
      : service = CallHistoryService.test(localDb: LocalDatabaseService());

  final CallHistoryService service;

  Future<void> cleanCalls() async {
    final calls = await LocalDatabaseService().getCalls();
    for (final call in calls) {
      final id = call['id'];
      if (id != null) {
        await LocalDatabaseService().deleteCall(id.toString());
      }
    }
  }
}
