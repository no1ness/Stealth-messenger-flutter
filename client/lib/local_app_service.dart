import 'dart:async';
import 'dart:typed_data';

import 'local_database_service.dart';
import 'logging/logger.dart';
import 'p2p_service.dart';
import 'services/attachments/attachment_service.dart';
import 'services/calls/call_history_service.dart';
import 'services/chat_management/chat_management_service.dart';
import 'services/contacts/contact_service.dart';
import 'services/crypto/group_secret_service.dart';
import 'services/monitoring/app_stats_push_service.dart';
import 'services/dashboard/dashboard_service.dart';
import 'services/device/device_info_service.dart';
import 'services/diagnostics/diagnostics_service.dart';
import 'services/identity/identity_service.dart';
import 'services/messaging/message_service.dart';
import 'storage_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pocketbase/pocketbase.dart';
import 'services/signaling/pocketbase_auth_service.dart';
import 'services/signaling/pocketbase_client.dart';
import 'services/user_directory/presence_service.dart';
import 'services/user_directory/user_directory_service.dart';

class LocalAppService {
  LocalAppService() {
    // Group-encryption callbacks route through GroupSecretService
    // (FIX_PLAN Phase D) — secrets live there, not in this facade.
    _messages.attachGroupCrypto(
      encryptGroup: _groupSecrets.encryptForGroup,
      decryptGroup: _groupSecrets.decryptForGroup,
    );
    _messages.attachAttachmentCompactor(_attachments.compactDescriptor);
    _attachments.attachGroupKeyResolver(_groupSecrets.resolve);
    _chatMgmt.attachGroupSecretKeyResolver(_groupSecrets.resolve);
    // Background workers must start AFTER all callback wiring is done so
    // they never observe a half-wired service. See `_kickoffBackgroundWorkers`.
    unawaited(_kickoffBackgroundWorkers());
    Logger.info('[app] diagnostics factory ready');
  }

  DiagnosticsService createDiagnostics() => DiagnosticsService(
        dashboardSummary: _dashboard.getDashboardSummary,
        attachmentDebugSummary: _attachments.getStorageDebugSummary,
        getUserId: _identity.getUserId,
        p2pActiveChannelCount: () => P2PService.instance.activeChannelCount,
        p2pRetryWorkerRunning: () => P2PService.instance.retryWorkerRunning,
        pocketbaseUrl: () => dotenv.env['POCKETBASE_URL']?.trim(),
      );

  Future<void> _kickoffBackgroundWorkers() async {
    try {
      await P2PService.instance.startRetryWorker();
    } catch (error) {
      Logger.debug(
        '[bootstrap] retry worker deferred (likely test env / DB unavailable)',
        extras: {'error': error},
      );
    }
    try {
      await _attachments.evictOldBlobs();
    } catch (error) {
      Logger.debug(
        '[bootstrap] attachment eviction deferred (likely test env / DB unavailable)',
        extras: {'error': error},
      );
    }
  }

  Future<void> _publishOwnProfile(String userId) async {
    final now = DateTime.now();
    if (_lastProfilePublishAt != null &&
        now.difference(_lastProfilePublishAt!).inMinutes < 5) {
      Logger.warn('[profile-publish] skipped by guard',
          extras: {'lastPublish': _lastProfilePublishAt!.toIso8601String()});
      return;
    }
    try {
      final pb = PocketBaseClient.instance.pb;
      final authService = PocketBaseAuthService(
        pocketBase: pb,
        storage: StorageService(),
      );
      await authService.ensureAuth(userId);

      final deviceInfo = await DeviceInfoService.instance.getDeviceInfo();
      final publicKey = await StorageService().read('publicKey');
      if (publicKey == null || publicKey.isEmpty) {
        Logger.warn('[profile-publish] publicKey missing, publishing without');
      }
      final registeredAt = await StorageService().read('registeredAt');
      final body = <String, dynamic>{
        'userId': userId,
        'deviceModel': deviceInfo.deviceModel,
        'platform': deviceInfo.platformType,
        'appVersion': deviceInfo.appVersion,
        'registeredAt': registeredAt ?? DateTime.now().toIso8601String(),
        'isOnline': true,
        'lastSeen': DateTime.now().toIso8601String(),
      };
      if (publicKey != null && publicKey.isNotEmpty) {
        body['publicKey'] = publicKey;
      }

      await _upsertProfile(pb, userId, body);
      _lastProfilePublishAt = now;
      Logger.info('[profile-publish] profile published',
          extras: {'userId': userId, 'deviceModel': deviceInfo.deviceModel});
    } catch (error) {
      Logger.warn('[profile-publish] error', extras: {'error': error});
    }
  }

  Future<void> _upsertProfile(
      PocketBase pb, String userId, Map<String, dynamic> body) async {
    try {
      final existing = await pb
          .collection('user_profiles')
          .getFirstListItem('userId="$userId"');
      await pb.collection('user_profiles').update(existing.id, body: body);
      Logger.debug('[profile-publish] profile updated');
    } catch (_) {
      await pb.collection('user_profiles').create(body: body);
      Logger.debug('[profile-publish] profile created');
    }
  }

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final IdentityService _identity = IdentityService();
  final ContactService _contacts = ContactService();
  final MessageService _messages = MessageService();
  final AttachmentService _attachments = AttachmentService();
  final CallHistoryService _callHistory = CallHistoryService();
  final ChatManagementService _chatMgmt = ChatManagementService();
  final DashboardService _dashboard = DashboardService();
  final GroupSecretService _groupSecrets = GroupSecretService();
  final UserDirectoryService _userDirectory = UserDirectoryService();
  final PresenceService _presence = PresenceService();

  AppStatsPushService? _statsPusher;
  Timer? _statsPushTimer;
  bool _pbWorkersStarted = false;
  DateTime? _lastProfilePublishAt;

  // Message-domain methods delegate to MessageService (task #6).
  Future<String> encryptMessage(String content, String otherUserId,
          {int? ratchetIndex}) =>
      _messages.encryptMessage(content, otherUserId,
          ratchetIndex: ratchetIndex);

  Future<String> decryptMessage(String payload, String otherUserId,
          {int? ratchetIndex, bool senderIsMe = false}) =>
      _messages.decryptMessage(payload, otherUserId,
          ratchetIndex: ratchetIndex, senderIsMe: senderIsMe);

  Future<Map<String, dynamic>> decryptRawMessage(Map<String, dynamic> row) =>
      _messages.decryptRawMessage(row);

  // Identity-domain methods delegate to IdentityService (task #5).
  Future<String?> getUserId() => _identity.getUserId();

  Future<String?> getNickname() => _identity.getNickname();

  Future<void> updateNickname(String nickname) async {
    await _identity.updateNickname(nickname);
    final me = await _identity.getUserId();
    if (me != null) _contacts.invalidateNicknameFor(me);
  }

  Future<void> registerUser(String nickname) =>
      _identity.registerUser(nickname);

  Future<void> startPBBasedWorkers() async {
    if (_pbWorkersStarted) return;
    _pbWorkersStarted = true;
    final me = await _identity.getUserId();
    if (me == null || me.isEmpty) return;
    try {
      await _publishOwnProfile(me);
      await _presence.start(me);
      final profiles = await _userDirectory.fetchAllProfiles(me);
      await _userDirectory.syncToLocalContacts(profiles);
      _presence.startHeartbeat();

      _statsPusher = AppStatsPushService();
      await _statsPusher!.pushStats();
      _statsPushTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
        await _statsPusher?.pushStats();
      });
      Logger.info('[stats-push] periodic push started (interval: 5 min)');
    } catch (error) {
      Logger.warn('[bootstrap] PB workers failed, will retry on next app start',
          extras: {'error': error});
    }
  }

  Future<void> logout() async {
    _statsPushTimer?.cancel();
    _statsPushTimer = null;
    _statsPusher = null;
    await _presence.setOffline();
    _presence.dispose();
    _userDirectory.clearCache();
    _pbWorkersStarted = false;
    _lastProfilePublishAt = null;
    await _identity.logout();
    _messages.clearCaches();
    _groupSecrets.clearOnLogout();
    _contacts.clearCaches();
  }

  Future<String> generateQRCode() => _identity.generateQRCode();

  // Chat-management methods delegate to ChatManagementService (FIX_PLAN A1).
  Future<String?> findOrCreatePrivateChatWith(String otherUserId) =>
      _chatMgmt.findOrCreatePrivateChatWith(otherUserId);

  Future<String?> createGroupChat(
          {required String name, required List<String> memberIds}) =>
      _chatMgmt.createGroupChat(name: name, memberIds: memberIds);

  Future<List<Map<String, dynamic>>> getChatMembers(String chatId) =>
      _chatMgmt.getChatMembers(chatId);

  Future<String?> getMyRoleInChat(String chatId) =>
      _chatMgmt.getMyRoleInChat(chatId);

  Future<void> addMembersToGroupChat(
          {required String chatId, required List<String> memberIds}) =>
      _chatMgmt.addMembersToGroupChat(chatId: chatId, memberIds: memberIds);

  Future<void> removeMemberFromGroupChat(
          {required String chatId, required String userId}) =>
      _chatMgmt.removeMemberFromGroupChat(chatId: chatId, userId: userId);

  Future<void> updateGroupMemberRole(
          {required String chatId,
          required String userId,
          required String role}) =>
      _chatMgmt.updateGroupMemberRole(
          chatId: chatId, userId: userId, role: role);

  Future<List<dynamic>> getChats() async {
    final chats = await _localDb.getChats();
    chats.sort(
      (a, b) => (b['updated_at']?.toString() ?? '')
          .compareTo(a['updated_at']?.toString() ?? ''),
    );
    return chats;
  }

  Future<List<dynamic>> getMessages(String chatId,
          {int limit = 40, int offset = 0}) =>
      _messages.getMessages(chatId, limit: limit, offset: offset);

  Future<void> sendMessage({
    required String chatId,
    required String content,
    required String type,
    String? replyToId,
    Map<String, dynamic>? metadataOverride,
  }) =>
      _messages.sendMessage(
        chatId: chatId,
        content: content,
        type: type,
        replyToId: replyToId,
        metadataOverride: metadataOverride,
      );

  Future<void> editMessage(
          {required String messageId,
          required String chatId,
          required String content}) =>
      _messages.editMessage(
          messageId: messageId, chatId: chatId, content: content);

  Future<void> softDeleteMessage({required String messageId}) =>
      _messages.softDeleteMessage(messageId: messageId);

  Future<void> pinMessage(
          {required String chatId, required String messageId}) =>
      _messages.pinMessage(chatId: chatId, messageId: messageId);

  Future<void> unpinMessage({required String chatId}) =>
      _messages.unpinMessage(chatId: chatId);

  Future<Map<String, dynamic>?> getPinnedMessage(String chatId) =>
      _messages.getPinnedMessage(chatId);

  // Attachment-domain methods delegate to AttachmentService (task #7).
  Future<String?> uploadAttachmentBytes({
    required Uint8List bytes,
    required String fileName,
    required String chatId,
    bool encrypt = true,
    bool? isGroupChat,
  }) =>
      _attachments.uploadBytes(
        bytes: bytes,
        fileName: fileName,
        chatId: chatId,
        encrypt: encrypt,
        isGroupChat: isGroupChat,
      );

  Future<Uint8List?> downloadAttachment(String url, String chatId,
          {bool encrypted = true, bool? isGroupChat}) =>
      _attachments.download(url, chatId,
          encrypted: encrypted, isGroupChat: isGroupChat);

  Future<Map<String, dynamic>> getStorageDebugSummary() =>
      _attachments.getStorageDebugSummary();

  // Dashboard-domain methods delegate to DashboardService (FIX_PLAN A2).
  Future<Map<String, dynamic>> getDashboardSummary() =>
      _dashboard.getDashboardSummary();

  Future<List<double>> getWeeklyActivityBars() =>
      _dashboard.getWeeklyActivityBars();

  Future<DateTime?> getLastSeen(String chatId) =>
      _dashboard.getLastSeen(chatId);

  Future<int> countUnreadSince(String chatId, DateTime since) async =>
      _dashboard.countUnreadSince(chatId, since, await _identity.getUserId());

  Future<Map<String, dynamic>?> fetchLastMessage(String chatId) =>
      _messages.fetchLastMessage(chatId);

  // Contact-domain methods delegate to ContactService (task #5).
  Future<List<dynamic>> getContacts() => _contacts.getContacts();

  Future<void> deleteContact(String userId) => _contacts.deleteContact(userId);

  Future<void> getNicknames(Set<String> userIds) =>
      _contacts.getNicknames(userIds);

  Future<String?> getNicknameForUser(String userId) =>
      _contacts.getNicknameForUser(userId);

  Future<String?> getUserNicknameById(String userId) =>
      _contacts.getUserNicknameById(userId);

  Future<String?> getUserNickname() => _contacts.getUserNickname();

  Future<String?> getSafetyNumber(String otherUserId) =>
      _contacts.getSafetyNumber(otherUserId);

  Future<void> addContact(String userId) => _contacts.addContact(userId);

  Future<List<dynamic>> searchUsers(String query) =>
      _contacts.searchUsers(query);

  Future<void> markChatRead(String chatId) => _messages.markChatRead(chatId);

  /// User-initiated retry of a failed outgoing 1:1 message (task #10).
  Future<void> retryNow(String messageId) => _messages.retryNow(messageId);

  Future<void> setTypingStatus(
      {required String chatId, required bool isTyping}) async {
    Logger.debug(
      '[local-only] typing status local-only',
      extras: {'chatId': chatId, 'isTyping': isTyping},
    );
  }

  Future<DateTime?> getOtherLastReadAt(String chatId) async => null;

  void subscribeP2PSignaling(String chatId) {
    unawaited(P2PService.instance.subscribeSignaling(chatId));
  }

  // Call-history methods delegate to CallHistoryService (task #7).
  Future<void> recordIncomingCall(
          {required String chatId,
          required String fromUserId,
          required String fromNickname}) =>
      _callHistory.recordIncomingCall(
        chatId: chatId,
        fromUserId: fromUserId,
        fromNickname: fromNickname,
      );

  Future<void> markIncomingCallDeclined(
          {required String chatId, required String fromUserId}) =>
      _callHistory.markIncomingCallDeclined(
          chatId: chatId, fromUserId: fromUserId);

  Future<void> markCurrentUserCallEnded({required String chatId}) =>
      _callHistory.markCurrentUserCallEnded(chatId: chatId);

  Future<List<Map<String, dynamic>>> getRecentCallHistory({int limit = 5}) =>
      _callHistory.getRecentCallHistory(limit: limit);
}
