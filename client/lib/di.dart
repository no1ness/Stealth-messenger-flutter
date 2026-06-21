import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/local_database_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/p2p_service.dart';
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
