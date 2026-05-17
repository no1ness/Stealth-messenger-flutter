// Dependency injection registry for the Stealth client.
//
// Purpose
// -------
//
// Centralise construction of the long-lived services (`StorageService`,
// `LocalDatabaseService`, `LocalAppService`, `P2PService`) behind
// Riverpod `Provider`s so that:
//
// 1. Screens read them via `ref.watch` / `ref.read` instead of building
//    fresh `LocalAppService()` instances ad-hoc (current pattern).
// 2. Tests can `ProviderScope(overrides: [...])` to inject fakes.
// 3. The singleton `P2PService.instance` becomes overridable for tests
//    without exposing a setter on the class itself.
//
// This file is intentionally thin: providers wrap existing constructors
// without changing service signatures. A future refactor may move
// internal dependencies (e.g. `LocalAppService` building its own
// `StorageService`/`LocalDatabaseService`) onto `ref` injection, but
// that is out of scope for the Phase 1 foundation.

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
///
/// Today `LocalAppService` builds its own `StorageService` and
/// `LocalDatabaseService` internally. We do **not** rewire those
/// dependencies here — that is a follow-up refactor. The provider
/// simply exposes a single shared instance.
final localAppServiceProvider = Provider<LocalAppService>((ref) {
  Logger.debug('[di] resolving localAppServiceProvider');
  return LocalAppService();
});

/// WebRTC DataChannel singleton used for direct P2P message delivery.
///
/// `P2PService.instance` is a process-wide singleton. Wrapping it in a
/// provider lets tests override with a fake via `ProviderScope`.
final p2pServiceProvider = Provider<P2PService>((ref) {
  Logger.debug('[di] resolving p2pServiceProvider');
  return P2PService.instance;
});

/// Broadcast stream of decrypted P2P messages from `P2PService`.
///
/// Phase 2 will replace the manual `StreamSubscription`/`setState` plumbing in
/// `chats_screen.dart` with `ref.listen(incomingP2PMessagesProvider, ...)`.
final incomingP2PMessagesProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final p2p = ref.watch(p2pServiceProvider);
  Logger.debug('[di] subscribing to p2p.onMessage');
  return p2p.onMessage;
});
