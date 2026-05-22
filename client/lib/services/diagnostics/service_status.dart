/// Health state for a single service surfaced in the diagnostics screen.
enum HealthState { ok, warn, error, unknown }

/// Snapshot of one service health at a moment in time.
class ServiceStatus {
  const ServiceStatus({
    required this.id,
    required this.label,
    required this.state,
    required this.detail,
    required this.at,
  });

  /// Stable machine id, used for sorting and equality in tests.
  /// e.g. `'database'`, `'p2p'`, `'pocketbase'`.
  final String id;

  /// Human-readable name shown in the UI.
  final String label;

  final HealthState state;

  /// Short context line (e.g. `'3 channels, retry worker on'`,
  /// `'POCKETBASE_URL not configured'`).
  final String detail;

  /// UTC instant the snapshot was collected.
  final DateTime at;
}
