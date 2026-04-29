import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database_service.dart';

/// Watches network connectivity and pushes offline-written messages to Supabase
/// when the connection is restored.
///
/// Lifecycle:
///   final sync = SyncService();
///   sync.start();          // call once at app startup
///   sync.dispose();        // call when app disposes
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isSyncing = false;
  Timer? _periodicTimer;
  int _syncIntervalSeconds = 30;

  /// Start listening for connectivity changes and periodic sync.
  void start() {
    _sub = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    
    _loadIntervalAndStart();

    // Also attempt a sync on startup in case we are already online
    // and there are pending messages from a previous offline session.
    _maybeSyncNow();
  }

  Future<void> _loadIntervalAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    _syncIntervalSeconds = prefs.getInt('syncIntervalSeconds') ?? 30;
    _startTimer();
  }

  void _startTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(Duration(seconds: _syncIntervalSeconds), (_) {
      debugPrint('[SyncService] Periodic sync triggered ($_syncIntervalSeconds s)');
      _maybeSyncNow();
    });
  }

  Future<void> setSyncInterval(int seconds) async {
    _syncIntervalSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('syncIntervalSeconds', seconds);
    _startTimer();
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = results.any(
      (r) => r != ConnectivityResult.none,
    );
    if (isOnline) {
      debugPrint('[SyncService] Connectivity restored — triggering sync');
      _maybeSyncNow();
    }
  }

  /// Push all pending (offline-written) messages to Supabase.
  Future<void> _maybeSyncNow() async {
    if (_isSyncing) return;

    final prefs = await SharedPreferences.getInstance();
    // If the user explicitly chose offline mode, do not auto-enable Supabase.
    final useSupabase = prefs.getBool('useSupabase') ?? true;
    if (!useSupabase) return;

    // Verify Supabase client is available (may not be initialised yet on first run).
    try {
      Supabase.instance.client; // throws if not initialised
    } catch (_) {
      return;
    }

    _isSyncing = true;
    try {
      await _syncPendingMessages();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncPendingMessages() async {
    final pending = await _localDb.getPendingSyncMessages();
    if (pending.isEmpty) return;

    debugPrint(
        '[SyncService] Syncing ${pending.length} offline message(s) to Supabase');

    final supabase = Supabase.instance.client;

    for (final message in pending) {
      final localKey = message['_local_key'];
      final payload = Map<String, dynamic>.from(message)..remove('_local_key');
      final messageId = payload['id']?.toString();
      try {
        // upsert so re-runs are idempotent
        await supabase.from('messages').upsert(payload);

        // Update chat's updated_at so list sorts correctly
        final chatId = payload['chat_id'] as String?;
        if (chatId != null) {
          await supabase.from('chats').update({
            'updated_at':
                payload['created_at'] ?? DateTime.now().toIso8601String()
          }).eq('id', chatId);
        }

        // Mark the local record as synced
        if (localKey != null) {
          await _localDb.markMessageSyncedByLocalKey(localKey);
        } else if (messageId != null) {
          await _localDb.markMessageSynced(messageId);
        }
        debugPrint('[SyncService] Synced message $messageId');
      } catch (e) {
        debugPrint('[SyncService] Failed to sync message $messageId: $e');
        // Continue with next — will retry on next connectivity event
      }
    }

    // Switch user back to online mode so subsequent messages go to Supabase
    await enableSupabase();
  }

  /// Programmatically re-enables Supabase sync (called after successful sync).
  Future<void> enableSupabase() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useSupabase', true);
    debugPrint('[SyncService] useSupabase re-enabled');
  }
}
