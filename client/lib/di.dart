import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/p2p_service.dart';
import 'package:stealth/services/signaling/incoming_call_service.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/services/signaling/webrtc_signaling_service.dart';
import 'package:stealth/storage_service.dart';

/// Project-wide secure key/value store (X25519 keys, PB tokens, etc.).
final storageServiceProvider = Provider<StorageService>((ref) {
  Logger.debug('[di] resolving storageServiceProvider');
  return StorageService();
});

/// Encrypted local database (messages, chats, contacts, calls).
final localDatabaseServiceProvider = Provider<LocalDatabaseService>((ref) {
  Logger.debug('[di] resolving localDatabaseServiceProvider');
  return LocalDatabaseService();
});

/// Application facade consumed by UI screens.
final localAppServiceProvider = Provider<LocalAppService>((ref) {
  Logger.debug('[di] resolving localAppServiceProvider');
  return LocalAppService();
});

/// WebRTC DataChannel singleton used for direct P2P message delivery.
final p2pServiceProvider = Provider<P2PService>((ref) {
  Logger.debug('[di] resolving p2pServiceProvider');
  return P2PService.instance;
});

/// Broadcast stream of decrypted P2P messages from `P2PService`.
final incomingP2PMessagesProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final p2p = ref.watch(p2pServiceProvider);
  Logger.debug('[di] subscribing to p2p.onMessage');
  return p2p.onMessage;
});

/// Self user ID from secure storage.
final selfUserIdProvider = FutureProvider<String?>((ref) async {
  final storage = ref.watch(storageServiceProvider);
  Logger.debug('[di] resolving selfUserIdProvider');
  try {
    final userId = await storage.read('userId');
    return userId;
  } catch (e) {
    Logger.warn('[di] selfUserIdProvider failed: $e');
    return null;
  }
});

/// Self user nickname from secure storage.
final selfNicknameProvider = FutureProvider<String?>((ref) async {
  final storage = ref.watch(storageServiceProvider);
  Logger.debug('[di] resolving selfNicknameProvider');
  try {
    final nickname = await storage.read('nickname');
    return nickname;
  } catch (e) {
    Logger.warn('[di] selfNicknameProvider failed: $e');
    return null;
  }
});

/// PocketBase client for signaling.
final pocketBaseClientProvider = Provider<PocketBaseClient>((ref) {
  Logger.debug('[di] resolving pocketBaseClientProvider');
  return PocketBaseClient.instance;
});

/// WebRTC signaling service.
final webRtcSignalingServiceProvider = Provider<WebRtcSignalingService>((ref) {
  Logger.debug('[di] resolving webRtcSignalingServiceProvider');
  final pbClient = ref.watch(pocketBaseClientProvider);
  final storage = ref.watch(storageServiceProvider);
  return WebRtcSignalingService(
    pocketBase: pbClient.pb,
    storage: storage,
  );
});

/// Incoming call signaling service.
final incomingCallServiceProvider = Provider<IncomingCallSignalingService>((ref) {
  Logger.debug('[di] resolving incomingCallServiceProvider');
  final pbClient = ref.watch(pocketBaseClientProvider);
  final storage = ref.watch(storageServiceProvider);
  return IncomingCallSignalingService(
    pocketBase: pbClient.pb,
    storage: storage,
  );
});
