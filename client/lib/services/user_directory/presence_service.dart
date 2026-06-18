import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/pocketbase_auth_service.dart';
import 'package:stealth/services/signaling/pocketbase_client.dart';
import 'package:stealth/storage_service.dart';

const String _kProfilesCollection = 'user_profiles';

class PresenceService with WidgetsBindingObserver {
  factory PresenceService() => _instance;
  PresenceService._({
    PocketBase? pocketBase,
    Connectivity? connectivity,
  })  : _pb = pocketBase ?? PocketBaseClient.instance.pb,
        _connectivity = connectivity ?? Connectivity(),
        _authService = PocketBaseAuthService(
          pocketBase: PocketBaseClient.instance.pb,
          storage: StorageService(),
        );

  @visibleForTesting
  PresenceService.test({
    required PocketBase pocketBase,
    required Connectivity connectivity,
    PocketBaseAuthService? authService,
  })  : _pb = pocketBase,
        _connectivity = connectivity,
        _authService = authService ?? PocketBaseAuthService(
          pocketBase: PocketBaseClient.instance.pb,
          storage: StorageService(),
        );

  static final PresenceService _instance = PresenceService._();

  PocketBase _pb;
  final Connectivity _connectivity;
  final PocketBaseAuthService _authService;

  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<void>? _reconfigureSub;
  UnsubscribeFunc? _unsubscribe;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  String? _selfUserId;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  static const int _heartbeatIntervalSeconds = 30;
  static const int _maxBackoffSeconds = 30;

  Stream<Map<String, dynamic>> get onPresenceChange =>
      _presenceController.stream;

  Future<void> start(String selfUserId) async {
    if (_disposed) return;
    Logger.info('[presence] start', extras: {'selfUserId': selfUserId});
    _selfUserId = selfUserId;

    await _authService.ensureAuth(selfUserId);
    await _subscribe();

    _connectivitySub ??= _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    _reconfigureSub ??= PocketBaseClient.onReconfigure.listen((_) {
      if (_selfUserId == null) return;
      _pb = PocketBaseClient.instance.pb;
      _authService.reconfigure(_pb);
      _scheduleReconnect(immediate: true);
    });

    WidgetsBinding.instance.addObserver(this);
  }

  void startHeartbeat() {
    if (_disposed || _selfUserId == null) return;
    Logger.info('[presence] heartbeat started',
        extras: {'interval': _heartbeatIntervalSeconds});
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _heartbeatIntervalSeconds),
      (_) => _upsertProfile({'isOnline': true, 'lastSeen': DateTime.now().toIso8601String()}),
    );
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> setOnline() async {
    Logger.info('[presence] setOnline');
    await _upsertProfile({
      'isOnline': true,
      'lastSeen': DateTime.now().toIso8601String(),
    });
    startHeartbeat();
  }

  Future<void> setOffline() async {
    Logger.info('[presence] setOffline');
    stopHeartbeat();
    await _upsertProfile({'isOnline': false});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(setOnline());
    } else if (state == AppLifecycleState.paused) {
      unawaited(setOffline());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    Logger.info('[presence] dispose');
    stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _reconfigureSub?.cancel();
    _reconfigureSub = null;
    WidgetsBinding.instance.removeObserver(this);

    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    if (unsubscribe != null) {
      try {
        await unsubscribe();
      } catch (error) {
        Logger.warn('[presence] unsubscribe error', extras: {'error': error});
      }
    }
    await _presenceController.close();
  }

  Future<void> _subscribe() async {
    final selfUserId = _selfUserId;
    if (selfUserId == null || _disposed) return;

    final previous = _unsubscribe;
    _unsubscribe = null;
    if (previous != null) {
      try {
        await previous();
      } catch (_) {}
    }

    Logger.info('[presence] subscribe');
    try {
      _unsubscribe = await _pb
          .collection(_kProfilesCollection)
          .subscribe('*', _onRecord)
          .timeout(const Duration(seconds: 8));
      _reconnectAttempt = 0;
    } on TimeoutException catch (error) {
      Logger.warn('[presence] subscribe timeout', extras: {'error': error});
      _scheduleReconnect();
    } catch (error) {
      Logger.warn('[presence] subscribe error', extras: {'error': error});
      _scheduleReconnect();
    }
  }

  void _onRecord(RecordSubscriptionEvent event) {
    if (_disposed) return;
    final record = event.record;
    if (record == null) return;
    if (event.action != 'create' && event.action != 'update') return;
    final userId = record.getStringValue('userId');
    if (userId.isEmpty || userId == _selfUserId) return;
    final profile = <String, dynamic>{
      'userId': userId,
      'isOnline': record.getBoolValue('isOnline'),
      'lastSeen': record.getStringValue('lastSeen'),
      'deviceModel': record.getStringValue('deviceModel'),
      'platform': record.getStringValue('platform'),
      'appVersion': record.getStringValue('appVersion'),
      'publicKey': record.getStringValue('publicKey'),
    };
    Logger.debug('[presence] presence change', extras: {'userId': userId, 'isOnline': profile['isOnline']});
    if (!_presenceController.isClosed) {
      _presenceController.add(profile);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    Logger.debug('[presence] connectivity changed',
        extras: {'hasNetwork': hasNetwork});
    if (hasNetwork) {
      _scheduleReconnect(immediate: true);
    }
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final delaySeconds = immediate
        ? 0
        : math.min(_maxBackoffSeconds, math.pow(2, _reconnectAttempt).toInt());
    _reconnectAttempt += 1;
    Logger.info('[presence] reconnect scheduled',
        extras: {'attempt': _reconnectAttempt, 'delaySeconds': delaySeconds});
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_disposed) return;
      await _subscribe();
    });
  }

  Future<void> _upsertProfile(Map<String, dynamic> body) async {
    final selfUserId = _selfUserId;
    if (selfUserId == null || _disposed) return;
    try {
      final existing = await _findProfileByUserId(selfUserId);
      if (existing != null) {
        await _pb
            .collection(_kProfilesCollection)
            .update(existing.id, body: body);
        Logger.debug('[presence] profile updated');
      } else {
        await _pb.collection(_kProfilesCollection).create(body: {
          ...body,
          'userId': selfUserId,
        });
        Logger.debug('[presence] profile created');
      }
    } catch (error) {
      Logger.warn('[presence] upsert error', extras: {'error': error});
    }
  }

  Future<RecordModel?> _findProfileByUserId(String userId) async {
    try {
      final result = await _pb
          .collection(_kProfilesCollection)
          .getFirstListItem('userId="$userId"');
      return result;
    } catch (_) {
      return null;
    }
  }
}
