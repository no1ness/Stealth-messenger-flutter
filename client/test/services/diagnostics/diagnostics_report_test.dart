import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/logging/log_buffer.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/diagnostics/app_environment_info.dart';
import 'package:stealth/services/diagnostics/diagnostics_report.dart';
import 'package:stealth/services/diagnostics/service_status.dart';

void main() {
  group('buildDiagnosticsReport', () {
    test('produces golden text with services and logs', () {
      final now = DateTime.utc(2026, 5, 22, 17, 30, 0);
      final env = const AppEnvironmentInfo(
        appVersion: '0.1.0',
        buildNumber: '1',
        platform: 'android',
        locale: 'en-US',
        logLevel: 'debug',
        pocketbaseHost: 'pb.example.com',
      );
      final statuses = [
        ServiceStatus(
          id: 'pocketbase',
          label: 'PocketBase signaling',
          state: HealthState.ok,
          detail: 'Host: pb.example.com',
          at: now,
        ),
        ServiceStatus(
          id: 'database',
          label: 'Local database',
          state: HealthState.ok,
          detail: 'Secure storage ready',
          at: now,
        ),
      ];
      final logs = [
        LogEntry(
          level: LogLevel.warn,
          timestampUtc: DateTime.utc(2026, 5, 22, 17, 29, 30),
          message: 'signaling reconnect',
          extrasText: ' attempt=3',
        ),
        LogEntry(
          level: LogLevel.error,
          timestampUtc: DateTime.utc(2026, 5, 22, 17, 29, 45),
          message: 'ICE failed',
        ),
      ];

      final report = buildDiagnosticsReport(
        statuses: statuses,
        logs: logs,
        env: env,
        now: now,
      );

      expect(report, '''
# Stealth Diagnostics Report
Generated: 2026-05-22T17:30:00.000Z
App: 0.1.0+1  Platform: android  Locale: en-US
Log level: debug  PocketBase host: pb.example.com

## Services
[OK   ] database (Local database) — Secure storage ready
[OK   ] pocketbase (PocketBase signaling) — Host: pb.example.com

## Recent log entries
2026-05-22T17:29:45.000Z [ERROR] ICE failed
2026-05-22T17:29:30.000Z [WARN] signaling reconnect attempt=3
''');
    });

    test('redacts inline UUID in log messages', () {
      final env = const AppEnvironmentInfo(
        appVersion: '0.1.0',
        buildNumber: '1',
        platform: 'android',
        locale: 'en-US',
        logLevel: 'debug',
        pocketbaseHost: null,
      );
      final logs = [
        LogEntry(
          level: LogLevel.warn,
          timestampUtc: DateTime.utc(2026, 5, 22, 17, 0, 0),
          message: 'chat 550e8400-e29b-41d4-a716-446655440000 dropped',
        ),
      ];
      final report = buildDiagnosticsReport(
        statuses: const [],
        logs: logs,
        env: env,
        now: DateTime.utc(2026, 5, 22, 17, 0, 0),
      );

      expect(report, isNot(contains('550e8400-e29b-41d4-a716')));
      expect(report, contains('chat …0000 dropped'));
    });

    test('renders (none) for empty logs and services', () {
      final env = const AppEnvironmentInfo(
        appVersion: '0.1.0',
        buildNumber: '1',
        platform: 'web',
        locale: 'en-US',
        logLevel: 'info',
        pocketbaseHost: null,
      );
      final report = buildDiagnosticsReport(
        statuses: const [],
        logs: const [],
        env: env,
        now: DateTime.utc(2026, 5, 22),
      );
      expect(report, contains('## Services\n(none)'));
      expect(report, contains('## Recent log entries\n(none)'));
      expect(report, contains('PocketBase host: unset'));
    });

    test('renders statuses sorted by id, logs newest-first', () {
      final env = const AppEnvironmentInfo(
        appVersion: '0.1.0',
        buildNumber: '1',
        platform: 'android',
        locale: 'en-US',
        logLevel: 'info',
        pocketbaseHost: 'pb',
      );
      final at = DateTime.utc(2026, 5, 22);
      final statuses = [
        ServiceStatus(
          id: 'zeta',
          label: 'Z',
          state: HealthState.ok,
          detail: '',
          at: at,
        ),
        ServiceStatus(
          id: 'alpha',
          label: 'A',
          state: HealthState.ok,
          detail: '',
          at: at,
        ),
      ];
      final logs = [
        LogEntry(
          level: LogLevel.warn,
          timestampUtc: DateTime.utc(2026, 5, 22, 1, 0, 0),
          message: 'older',
        ),
        LogEntry(
          level: LogLevel.warn,
          timestampUtc: DateTime.utc(2026, 5, 22, 2, 0, 0),
          message: 'newer',
        ),
      ];
      final report = buildDiagnosticsReport(
        statuses: statuses,
        logs: logs,
        env: env,
        now: at,
      );
      final alphaIdx = report.indexOf('alpha');
      final zetaIdx = report.indexOf('zeta');
      expect(alphaIdx, lessThan(zetaIdx));
      final newerIdx = report.indexOf('newer');
      final olderIdx = report.indexOf('older');
      expect(newerIdx, lessThan(olderIdx));
    });
  });
}
