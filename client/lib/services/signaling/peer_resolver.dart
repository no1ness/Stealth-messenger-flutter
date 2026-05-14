import 'package:flutter/foundation.dart' show debugPrint;
import 'package:stealth/local_database_service.dart';

/// Бросается, когда `PeerResolver` не смог определить второго участника
/// чата для сигналинга — обычно это означает, что чат ещё не
/// синхронизирован в локальную БД (свежий контакт без `getChats()`).
class PeerResolutionException implements Exception {
  PeerResolutionException(this.message);

  final String message;

  @override
  String toString() => 'PeerResolutionException: $message';
}

/// Резолв `targetUserId` (UUID собеседника) по `chatId`. Чисто локальный
/// путь — читает из IndexedDB / sqflite через `LocalDatabaseService`.
///
/// Это локальная точка резолва peer id для call/datachannel сигналинга.
///
/// Ограничение: чат должен быть закэширован локально. Это происходит при
/// любом `LocalAppService.getChats()` (см. поле `members[]` в чат-объекте),
/// поэтому в нормальном flow приложения чат уже есть к моменту инициации
/// звонка. Если нет — UI должен поймать [PeerResolutionException] и
/// показать сообщение «Cannot start call: contact not synced yet».
class PeerResolver {
  PeerResolver({LocalDatabaseService? localDb})
      : _localDb = localDb ?? LocalDatabaseService();

  final LocalDatabaseService _localDb;

  Future<String> resolveTarget({
    required String chatId,
    required String selfUserId,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) {
      throw PeerResolutionException(
        'chat $chatId not found in local DB — synced contacts list first',
      );
    }
    final rawMembers = chat['members'];
    final members = <String>[];
    if (rawMembers is List) {
      for (final m in rawMembers) {
        if (m is String && m.isNotEmpty) members.add(m);
      }
    }
    final target = members.firstWhere(
      (m) => m != selfUserId,
      orElse: () => '',
    );
    if (target.isEmpty) {
      throw PeerResolutionException(
        'chat $chatId has no peer member (members=$members, self=$selfUserId)',
      );
    }
    debugPrint(
      '[signaling] resolved target for chatId=$chatId → $target',
    );
    return target;
  }
}
