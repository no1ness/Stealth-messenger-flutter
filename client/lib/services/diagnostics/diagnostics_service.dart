// Aggregates health snapshots for the in-app diagnostics screen.
//
// The constructor takes provider closures instead of concrete service
// instances so unit tests can inject fakes without rebuilding the
// project's whole DI graph. See `local_app_service.dart#createDiagnostics`
// for the production wiring (method tear-offs + dotenv lambdas).
//
// Lifecycle: caller owns the instance. `LocalAppService.createDiagnostics`
// returns a fresh service per `DiagnosticsScreen` open; the screen's
// State.dispose() calls `dispose()`. Service is NOT a singleton —
// multiple-open without dispose would leak `Timer.periodic` instances.

import 'dart:async';

import '../../logging/logger.dart';
import 'service_status.dart';

class DiagnosticsService {
  DiagnosticsService({
    required this.dashboardSummary,
    required this.attachmentDebugSummary,
    required this.getUserId,
    required this.p2pActiveChannelCount,
    required this.p2pRetryWorkerRunning,
    required this.pocketbaseUrl,
    this.pollInterval = const Duration(seconds: 5),
  });

  /// `DashboardService.getDashboardSummary` tear-off in production.
  final Future<Map<String, dynamic>> Function() dashboardSummary;

  /// `AttachmentService.getStorageDebugSummary` tear-off in production.
  final Future<Map<String, dynamic>> Function() attachmentDebugSummary;

  /// `IdentityService.getUserId` tear-off in production.
  final Future<String?> Function() getUserId;

  /// `() => P2PService.instance.activeChannelCount` in production.
  final int Function() p2pActiveChannelCount;

  /// `() => P2PService.instance.retryWorkerRunning` in production.
  final bool Function() p2pRetryWorkerRunning;

  /// `() => dotenv.env['POCKETBASE_URL']?.trim()` in production.
  /// Reads dotenv directly to avoid triggering `PocketBaseClient.instance`,
  /// which throws StateError on a missing URL.
  final String? Function() pocketbaseUrl;

  final Duration pollInterval;

  StreamController<List<ServiceStatus>>? _controller;
  Timer? _timer;
  bool _collectInProgress = false;
  final Map<String, HealthState> _lastStates = {};

  List<ServiceStatus>? _lastKnownSnapshot;

  /// Most recent snapshot, or null before the first emit. Exposed so
  /// `StreamBuilder.initialData` can avoid the 5-second loading gap on
  /// the diagnostics screen.
  List<ServiceStatus>? get lastKnownSnapshot => _lastKnownSnapshot;

  /// Broadcast stream of health snapshots. On every new listener, an
  /// immediate snapshot is pushed via `onListen`, so callers don't wait
  /// for the periodic tick to see the first value. Additional emissions
  /// arrive every [pollInterval].
  Stream<List<ServiceStatus>> watch() {
    _controller ??= StreamController<List<ServiceStatus>>.broadcast(
      onListen: () {
        // Kick off an immediate collection for the new listener.
        unawaited(_emitOnce());
        // Start the periodic tick lazily so disposing before any
        // listener subscribes leaves no timers behind.
        _timer ??= Timer.periodic(pollInterval, (_) {
          unawaited(_emitOnce());
        });
      },
    );
    return _controller!.stream;
  }

  /// One-shot pull, also used internally by [watch].
  Future<List<ServiceStatus>> snapshot() => _collect();

  Future<void> _emitOnce() async {
    if (_controller == null || _controller!.isClosed) return;
    final result = await _collect();
    if (_controller != null && !_controller!.isClosed) {
      _controller!.add(result);
    }
  }

  Future<List<ServiceStatus>> _collect() async {
    // Re-entrance guard: if a slow source is still running, drop the
    // new tick rather than firing parallel `Future.wait`s.
    if (_collectInProgress) {
      return _lastKnownSnapshot ?? const [];
    }
    _collectInProgress = true;
    try {
      final at = DateTime.now().toUtc();
      final results = await Future.wait<ServiceStatus>([
        _collectDatabase(at),
        _collectAttachments(at),
        _collectIdentity(at),
        _collectP2P(at),
        _collectPocketBase(at),
      ]);
      results.sort((a, b) => a.id.compareTo(b.id));
      _lastKnownSnapshot = List<ServiceStatus>.unmodifiable(results);

      // Log transitions (warn-level visibility into health changes).
      for (final status in results) {
        final prev = _lastStates[status.id];
        if (prev != null && prev != status.state) {
          Logger.warn('[diag] state changed', extras: {
            'id': status.id,
            'from': prev.name,
            'to': status.state.name,
            'detail': status.detail,
          });
        }
        _lastStates[status.id] = status.state;
      }
      Logger.debug('[diag] snapshot composed',
          extras: {'count': results.length});
      return _lastKnownSnapshot!;
    } finally {
      _collectInProgress = false;
    }
  }

  Future<ServiceStatus> _collectDatabase(DateTime at) async {
    try {
      final summary = await dashboardSummary();
      final ready = summary['secureStorageReady'] == true;
      return ServiceStatus(
        id: 'database',
        label: 'Local database',
        state: ready ? HealthState.ok : HealthState.error,
        detail: ready
            ? 'Secure storage ready'
            : 'Secure storage not ready (private key missing?)',
        at: at,
      );
    } catch (error) {
      Logger.error('[diag] database snapshot failed',
          extras: {'error': error});
      return ServiceStatus(
        id: 'database',
        label: 'Local database',
        state: HealthState.error,
        detail: '$error',
        at: at,
      );
    }
  }

  Future<ServiceStatus> _collectAttachments(DateTime at) async {
    try {
      final summary = await attachmentDebugSummary();
      final fileCount = summary['fileCount'];
      return ServiceStatus(
        id: 'attachments',
        label: 'Encrypted attachments',
        state: HealthState.ok,
        detail: '$fileCount attachments tracked',
        at: at,
      );
    } catch (error) {
      Logger.error('[diag] attachments snapshot failed',
          extras: {'error': error});
      return ServiceStatus(
        id: 'attachments',
        label: 'Encrypted attachments',
        state: HealthState.error,
        detail: '$error',
        at: at,
      );
    }
  }

  Future<ServiceStatus> _collectIdentity(DateTime at) async {
    try {
      final uid = await getUserId();
      return ServiceStatus(
        id: 'identity',
        label: 'Local identity',
        state: uid != null ? HealthState.ok : HealthState.error,
        detail: uid != null ? 'User id loaded' : 'No user id (not registered?)',
        at: at,
      );
    } catch (error) {
      Logger.error('[diag] identity snapshot failed',
          extras: {'error': error});
      return ServiceStatus(
        id: 'identity',
        label: 'Local identity',
        state: HealthState.error,
        detail: '$error',
        at: at,
      );
    }
  }

  Future<ServiceStatus> _collectP2P(DateTime at) async {
    try {
      final channels = p2pActiveChannelCount();
      final retry = p2pRetryWorkerRunning();
      return ServiceStatus(
        id: 'p2p',
        label: 'P2P data channels',
        state: retry ? HealthState.ok : HealthState.warn,
        detail: '$channels channels, retry worker ${retry ? "on" : "off"}',
        at: at,
      );
    } catch (error) {
      Logger.error('[diag] p2p snapshot failed', extras: {'error': error});
      return ServiceStatus(
        id: 'p2p',
        label: 'P2P data channels',
        state: HealthState.error,
        detail: '$error',
        at: at,
      );
    }
  }

  Future<ServiceStatus> _collectPocketBase(DateTime at) async {
    try {
      final raw = pocketbaseUrl();
      if (raw == null || raw.isEmpty) {
        return ServiceStatus(
          id: 'pocketbase',
          label: 'PocketBase signaling',
          state: HealthState.error,
          detail: 'POCKETBASE_URL not configured',
          at: at,
        );
      }
      final authority = Uri.tryParse(raw)?.authority;
      final detail = authority == null || authority.isEmpty
          ? 'URL: $raw'
          : 'Host: $authority';
      return ServiceStatus(
        id: 'pocketbase',
        label: 'PocketBase signaling',
        state: HealthState.ok,
        detail: detail,
        at: at,
      );
    } catch (error) {
      Logger.error('[diag] pocketbase snapshot failed',
          extras: {'error': error});
      return ServiceStatus(
        id: 'pocketbase',
        label: 'PocketBase signaling',
        state: HealthState.error,
        detail: '$error',
        at: at,
      );
    }
  }

  /// Tears down the periodic timer and broadcast controller. Safe to
  /// call multiple times.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }
}
