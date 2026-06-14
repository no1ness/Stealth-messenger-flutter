// Builds the plain-text diagnostics report shipped via the share intent
// on the in-app diagnostics screen.
//
// Two-line security contract:
// 1. Every log line passes through `scrubInlineSensitive` from
//    `log_scrubber.dart` before being written, so inline UUIDs / PB ids
//    / base64 public keys interpolated into log messages don't leak to
//    third-party messengers.
// 2. Output is deterministic — statuses sorted by `id`, logs by time
//    descending — so the unit-test golden compare is stable.

import '../../logging/log_buffer.dart';
import '../../logging/logger.dart';
import 'app_environment_info.dart';
import 'log_scrubber.dart';
import 'service_status.dart';

String _stateMarker(HealthState s) {
  switch (s) {
    case HealthState.ok:
      return 'OK   ';
    case HealthState.warn:
      return 'WARN ';
    case HealthState.error:
      return 'ERROR';
    case HealthState.unknown:
      return '?    ';
  }
}

/// Assembles the full diagnostics report string.
///
/// [now] — override for deterministic timestamps in tests.
String buildDiagnosticsReport({
  required List<ServiceStatus> statuses,
  required List<LogEntry> logs,
  required AppEnvironmentInfo env,
  DateTime? now,
}) {
  final generatedAt = (now ?? DateTime.now().toUtc()).toIso8601String();
  final buf = StringBuffer();

  buf.writeln('# Stealth Diagnostics Report');
  buf.writeln('Generated: $generatedAt');
  buf.writeln(
      'App: ${env.appVersion}+${env.buildNumber}  Platform: ${env.platform}'
      '  Locale: ${env.locale}');
  buf.writeln('Log level: ${env.logLevel}  PocketBase host: '
      '${env.pocketbaseHost ?? "unset"}');
  buf.writeln();

  final sortedStatuses = [...statuses]
    ..sort((a, b) => a.id.compareTo(b.id));
  buf.writeln('## Services');
  if (sortedStatuses.isEmpty) {
    buf.writeln('(none)');
  } else {
    for (final s in sortedStatuses) {
      buf.writeln('[${_stateMarker(s.state)}] ${s.id} '
          '(${s.label}) — ${s.detail}');
    }
  }
  buf.writeln();

  final sortedLogs = [...logs]
    ..sort((a, b) => b.timestampUtc.compareTo(a.timestampUtc));
  buf.writeln('## Recent log entries');
  if (sortedLogs.isEmpty) {
    buf.writeln('(none)');
  } else {
    for (final entry in sortedLogs) {
      final scrubbed = scrubInlineSensitive(entry.formattedLine);
      buf.writeln('${entry.timestampUtc.toIso8601String()} $scrubbed');
    }
  }

  final report = buf.toString();
  Logger.debug('[diag.report] composed', extras: {
    'bytes': report.length,
    'logsCount': sortedLogs.length,
    'statusesCount': sortedStatuses.length,
  });
  return report;
}
