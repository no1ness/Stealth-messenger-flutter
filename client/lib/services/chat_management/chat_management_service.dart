import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../../local_database_service.dart';
import '../../logging/logger.dart';
import '../contacts/contact_service.dart';
import '../identity/identity_service.dart';

/// Group-secret resolver signature. Caller supplies a closure (typically
/// wired from [LocalAppService] which still owns the in-memory cache and
/// the `flutter_secure_storage_x` write path); [createGroupChat]
/// invokes it synchronously before the chat row is committed to the
/// database so the secret is materialised eagerly.
typedef GroupSecretKeyResolver = Future<SecretKey> Function(String chatId);

/// Private/group chat lifecycle facade extracted from `LocalAppService`
/// (FIX_PLAN Phase A task A1). Keeps the no-arg factory-singleton
/// convention used by the other extracted services so existing call
/// sites delegate without changes.
///
/// Stateful methods touch [LocalDatabaseService]; their unit coverage
/// lives in the existing widget/integration tests. Only the
/// callback contract (`createGroupChat` invokes the resolver exactly
/// once, synchronously, before the chat row hits the DB) is locked
/// down here via [chat_management_service_test.dart].
class ChatManagementService {
  factory ChatManagementService() => _instance;
  ChatManagementService._();
  static final ChatManagementService _instance = ChatManagementService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final IdentityService _identity = IdentityService();
  final ContactService _contacts = ContactService();
  final Uuid _uuid = const Uuid();

  GroupSecretKeyResolver? _groupSecretResolver;

  /// Wire the group-secret callback. Called once from
  /// `LocalAppService()` constructor; the resolver itself still owns
  /// the in-memory `_groupSecretCache` + persistent storage write path
  /// so we don't duplicate that state across services. Symmetric with
  /// `AttachmentService.attachGroupKeyResolver` (task #7).
  void attachGroupSecretKeyResolver(GroupSecretKeyResolver resolver) {
    _groupSecretResolver = resolver;
  }

  Future<String?> findOrCreatePrivateChatWith(String otherUserId) async {
    final me = await _identity.getUserId();
    if (me == null || me.isEmpty || otherUserId.isEmpty) {
      return null;
    }
    final existing = await _localDb.getChats();
    for (final chat in existing) {
      final isPrivate = chat['is_private'] as bool? ?? false;
      final members = (chat['members'] as List<dynamic>? ?? [])
          .map((member) => member.toString())
          .toSet();
      if (isPrivate && members.contains(me) && members.contains(otherUserId)) {
        return chat['id']?.toString();
      }
    }

    final now = DateTime.now().toIso8601String();
    final chatId = _uuid.v4();
    await _localDb.saveChat({
      'id': chatId,
      'name': null,
      'is_private': true,
      'members': [me, otherUserId],
      'created_at': now,
      'updated_at': now,
      'last_read_at': now,
    });
    Logger.info(
      '[chat-management] created private chat',
      extras: {'chatId': chatId},
    );
    return chatId;
  }

  Future<String?> createGroupChat({
    required String name,
    required List<String> memberIds,
  }) async {
    final me = await _identity.getUserId();
    if (me == null || me.isEmpty) return null;
    final resolver = _groupSecretResolver;
    if (resolver == null) {
      throw StateError(
        '[chat-management] createGroupChat called before '
        'attachGroupSecretKeyResolver wiring',
      );
    }
    final members = <String>{me, ...memberIds}.toList();
    final chatId = _uuid.v4();

    // Materialise the group secret synchronously BEFORE persisting the
    // chat row. Contract locked down in
    // `chat_management_service_test.dart` — keeps the resolver
    // observable + deterministic for future Double Ratchet migration.
    await resolver(chatId);

    final now = DateTime.now().toIso8601String();
    await _localDb.saveChat({
      'id': chatId,
      'name': name.trim().isEmpty ? 'Group' : name.trim(),
      'is_private': false,
      'members': members,
      'created_at': now,
      'updated_at': now,
      'last_read_at': now,
      'roles': {for (final id in members) id: id == me ? 'admin' : 'member'},
    });
    Logger.info(
      '[chat-management] created group chat',
      extras: {'chatId': chatId, 'memberCount': members.length},
    );
    return chatId;
  }

  Future<List<Map<String, dynamic>>> getChatMembers(String chatId) async {
    final chat = await _localDb.getChatById(chatId);
    final members = (chat?['members'] as List<dynamic>? ?? [])
        .map((member) => member.toString())
        .toList();
    final roles = chat?['roles'] as Map<dynamic, dynamic>? ?? const {};
    return Future.wait(
      members.map((id) async {
        return {
          'user_id': id,
          'nickname': await _contacts.getNicknameForUser(id) ?? id,
          'role': roles[id]?.toString() ?? 'member',
        };
      }),
    );
  }

  Future<String?> getMyRoleInChat(String chatId) async {
    final me = await _identity.getUserId();
    final chat = await _localDb.getChatById(chatId);
    final roles = chat?['roles'] as Map<dynamic, dynamic>? ?? const {};
    return roles[me]?.toString() ?? 'member';
  }

  Future<void> addMembersToGroupChat({
    required String chatId,
    required List<String> memberIds,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    final members = (chat['members'] as List<dynamic>? ?? [])
        .map((member) => member.toString())
        .toSet()
      ..addAll(memberIds);
    chat['members'] = members.toList();
    chat['updated_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }

  Future<void> removeMemberFromGroupChat({
    required String chatId,
    required String userId,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    final members = (chat['members'] as List<dynamic>? ?? [])
        .map((member) => member.toString())
        .where((member) => member != userId)
        .toList();
    chat['members'] = members;
    chat['updated_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }

  Future<void> updateGroupMemberRole({
    required String chatId,
    required String userId,
    required String role,
  }) async {
    final chat = await _localDb.getChatById(chatId);
    if (chat == null) return;
    final roles = Map<String, dynamic>.from(chat['roles'] as Map? ?? {});
    roles[userId] = role;
    chat['roles'] = roles;
    chat['updated_at'] = DateTime.now().toIso8601String();
    await _localDb.saveChat(chat);
  }
}
