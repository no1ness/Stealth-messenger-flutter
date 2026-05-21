import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../local_database_service.dart';
import '../../logging/logger.dart';

/// Local call-log facade: records incoming, declined, and ended calls
/// into the `calls` store and surfaces the recent-history list.
///
/// Singleton — backing storage is [LocalDatabaseService]. The companion
/// signaling stays in `WebRtcSignalingService` / `IncomingCallService`;
/// this service only persists the history rows for the UI.
///
/// Extracted from `LocalAppService` as task #7 of the post-PocketBase
/// hardening plan (`.ai-factory/plans/client-hardening-followup.md`).
class CallHistoryService {
  factory CallHistoryService() => _instance;
  CallHistoryService._();
  static final CallHistoryService _instance = CallHistoryService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final Uuid _uuid = const Uuid();

  Future<void> recordIncomingCall({
    required String chatId,
    required String fromUserId,
    required String fromNickname,
  }) async {
    Logger.debug('[calls] recordIncomingCall', extras: {
      'chatId': chatId,
      'fromUserId': fromUserId,
    });
    await _localDb.saveCall({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'direction': 'incoming',
      'status': 'initiated',
      'peer_user_id': fromUserId,
      'peer_nickname': fromNickname,
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> markIncomingCallDeclined({
    required String chatId,
    required String fromUserId,
  }) async {
    Logger.debug('[calls] markIncomingCallDeclined', extras: {
      'chatId': chatId,
      'fromUserId': fromUserId,
    });
    await _localDb.saveCall({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'direction': 'incoming',
      'status': 'declined',
      'peer_user_id': fromUserId,
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> markCurrentUserCallEnded({required String chatId}) async {
    Logger.debug('[calls] markCurrentUserCallEnded', extras: {'chatId': chatId});
    await _localDb.saveCall({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'direction': 'local',
      'status': 'ended',
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getRecentCallHistory({int limit = 5}) async {
    final calls = await _localDb.getCalls();
    calls.sort(
      (a, b) => (b['started_at']?.toString() ?? '')
          .compareTo(a['started_at']?.toString() ?? ''),
    );
    return calls.take(limit).toList();
  }
}
