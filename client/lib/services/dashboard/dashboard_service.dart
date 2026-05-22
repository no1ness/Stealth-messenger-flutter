import 'dart:async';

import '../../local_database_service.dart';
import '../../storage_service.dart';

/// Analytics rollups used by the settings/profile dashboards. Extracted
/// from `LocalAppService` (FIX_PLAN Phase A task A2) — kept deliberately
/// thin so the next iteration can split the pure aggregator (e.g.
/// [computeWeeklyBars]) for unit coverage without touching the storage
/// surface.
///
/// Stateful methods touch [LocalDatabaseService] / [StorageService];
/// they are covered through the widget/integration suite. The pure
/// helper(s) below are testable in isolation.
class DashboardService {
  factory DashboardService() => _instance;
  DashboardService._();
  static final DashboardService _instance = DashboardService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final StorageService _storage = StorageService();

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final chats = await _localDb.getChats();
    final contacts = await _localDb.getContacts();
    final calls = await _localDb.getCalls();
    var messageCount = 0;
    for (final chat in chats) {
      messageCount += (await _localDb.getMessages(chat['id'].toString())).length;
    }
    return {
      'chatCount': chats.length,
      'contactCount': contacts.length,
      'messageCount': messageCount,
      'callCount': calls.length,
      'localMediaReady': true,
      'bucketReady': true,
      'secureStorageReady': await _storage.read('privateKey') != null,
    };
  }

  Future<List<double>> getWeeklyActivityBars() async {
    final timestamps = <DateTime>[];
    for (final chat in await _localDb.getChats()) {
      for (final message in await _localDb.getMessages(chat['id'].toString())) {
        final created = DateTime.tryParse(
            message['created_at']?.toString() ?? '');
        if (created != null) timestamps.add(created);
      }
    }
    return computeWeeklyBars(timestamps, now: DateTime.now());
  }

  Future<DateTime?> getLastSeen(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    return DateTime.tryParse(chat?['last_read_at']?.toString() ?? '');
  }

  Future<int> countUnreadSince(
      String chatId, DateTime since, String? myUserId) async {
    final messages = await _localDb.getMessages(chatId);
    return messages.where((message) {
      final created = DateTime.tryParse(message['created_at']?.toString() ?? '');
      return message['sender_id'] != myUserId &&
          created != null &&
          created.isAfter(since);
    }).length;
  }
}

/// Pure aggregator: convert a flat list of message timestamps into 7
/// normalised activity bars (oldest → newest). Empty buckets receive a
/// minimum visible value of `0.12` so the chart never flatlines.
///
/// Unit-tested in `client/test/services/dashboard_service_test.dart`.
List<double> computeWeeklyBars(
  List<DateTime> timestamps, {
  required DateTime now,
}) {
  final counts = List<int>.filled(7, 0);
  for (final created in timestamps) {
    final diff = now.difference(created).inDays;
    if (diff >= 0 && diff < 7) {
      counts[6 - diff] += 1;
    }
  }
  final maxCount =
      counts.fold<int>(1, (max, value) => value > max ? value : max);
  return counts
      .map((count) => count == 0 ? 0.12 : count / maxCount)
      .toList();
}
