import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/logging/log_buffer.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/diagnostics/app_environment_info.dart';
import 'package:stealth/services/diagnostics/diagnostics_service.dart';
import 'package:stealth/services/diagnostics/diagnostics_share.dart';
import 'package:stealth/services/diagnostics/service_status.dart';
import 'package:stealth/ui/screens/diagnostics/diagnostics_screen.dart';
import 'package:stealth/ui/screens/diagnostics/widgets/log_entry_tile.dart';
import 'package:stealth/ui/screens/diagnostics/widgets/service_status_tile.dart';

void main() {
  late _FakeDiagnosticsService fake;
  late List<({BuildContext context, String text})> shareCalls;

  setUp(() {
    LogBuffer.instance.clearForTests();
    shareCalls = <({BuildContext context, String text})>[];
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  DiagnosticsScreen buildScreen({
    List<ServiceStatus>? statuses,
    List<LogEntry> logs = const [],
  }) {
    fake = _FakeDiagnosticsService(initial: statuses ?? _defaultStatuses());
    return DiagnosticsScreen(
      diagnostics: fake,
      logProvider: ({required min, limit}) => logs
          .where((e) => e.level.index >= min.index)
          .take(limit ?? logs.length)
          .toList(),
      shareInvoker: (ctx, text) async {
        shareCalls.add((context: ctx, text: text));
        return ShareOutcome.shared;
      },
      envProvider: () async => const AppEnvironmentInfo(
        appVersion: '0.0.0-test',
        buildNumber: '0',
        platform: 'test',
        locale: 'en-US',
        logLevel: 'debug',
        pocketbaseHost: 'pb.test',
      ),
    );
  }

  testWidgets('renders ServiceStatusTile per status', (tester) async {
    await tester.pumpWidget(wrap(buildScreen()));
    await tester.pump();
    expect(find.byType(ServiceStatusTile), findsNWidgets(3));
  });

  testWidgets('LogEntryTile shows level/message/time fields', (tester) async {
    final logs = [
      LogEntry(
        level: LogLevel.warn,
        timestampUtc: DateTime.utc(2026, 5, 22, 17, 30, 45),
        message: 'reconnect attempt',
      ),
    ];
    await tester.pumpWidget(wrap(buildScreen(logs: logs)));
    await tester.pump();

    expect(find.byType(LogEntryTile), findsOneWidget);
    expect(find.text('WARN'), findsOneWidget);
    expect(find.text('17:30:45'), findsOneWidget);
    expect(find.text('reconnect attempt'), findsOneWidget);
  });

  testWidgets('filter chip "Errors" hides WARN entries', (tester) async {
    final logs = [
      LogEntry(
        level: LogLevel.warn,
        timestampUtc: DateTime.utc(2026, 5, 22, 1, 0, 0),
        message: 'warn line',
      ),
      LogEntry(
        level: LogLevel.error,
        timestampUtc: DateTime.utc(2026, 5, 22, 2, 0, 0),
        message: 'error line',
      ),
    ];
    await tester.pumpWidget(wrap(buildScreen(logs: logs)));
    await tester.pump();

    expect(find.byType(LogEntryTile), findsNWidgets(2));

    await tester.tap(find.text('Errors'));
    await tester.pump();

    expect(find.byType(LogEntryTile), findsOneWidget);
    expect(find.text('warn line'), findsNothing);
    expect(find.text('error line'), findsOneWidget);
  });

  testWidgets('empty buffer shows "No log entries yet"', (tester) async {
    await tester.pumpWidget(wrap(buildScreen()));
    await tester.pump();
    expect(find.text('No log entries yet'), findsOneWidget);
  });

  testWidgets('"Share logs" invokes shareInvoker with report text',
      (tester) async {
    await tester.pumpWidget(wrap(buildScreen()));
    await tester.pump();

    await tester.tap(find.text('Share logs'));
    // Don't pumpAndSettle — the CircularProgressIndicator on the
    // sharing-in-progress button never finishes its animation. Pump
    // a few frames for the async work to land.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(shareCalls, hasLength(1));
    expect(shareCalls.first.text,
        contains('# Stealth Diagnostics Report'));
  });

  testWidgets('status dot carries a semantic label per HealthState',
      (tester) async {
    await tester.pumpWidget(wrap(buildScreen()));
    await tester.pump();

    // Three OK statuses in the default fixture → three Semantics nodes
    // each labeled 'OK'.
    final okLabels = find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.label ?? '') == 'OK',
    );
    expect(okLabels, findsNWidgets(3));
  });

  testWidgets('screen does NOT dispose externally-owned service',
      (tester) async {
    await tester.pumpWidget(wrap(buildScreen()));
    await tester.pump();
    expect(fake.disposeCalls, 0);
    // Replace widget tree -> state.dispose runs.
    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    expect(fake.disposeCalls, 0,
        reason: 'caller-owned service must not be disposed by the screen');
  });
}

List<ServiceStatus> _defaultStatuses() {
  final at = DateTime.utc(2026, 5, 22);
  return [
    ServiceStatus(
      id: 'database',
      label: 'Local database',
      state: HealthState.ok,
      detail: 'Secure storage ready',
      at: at,
    ),
    ServiceStatus(
      id: 'p2p',
      label: 'P2P data channels',
      state: HealthState.ok,
      detail: '0 channels, retry worker on',
      at: at,
    ),
    ServiceStatus(
      id: 'pocketbase',
      label: 'PocketBase signaling',
      state: HealthState.ok,
      detail: 'Host: pb.example.com',
      at: at,
    ),
  ];
}

class _FakeDiagnosticsService implements DiagnosticsService {
  _FakeDiagnosticsService({required this.initial});
  final List<ServiceStatus> initial;
  int disposeCalls = 0;

  @override
  List<ServiceStatus>? get lastKnownSnapshot => initial;

  @override
  Stream<List<ServiceStatus>> watch() => Stream.value(initial);

  @override
  Future<List<ServiceStatus>> snapshot() async => initial;

  @override
  void dispose() {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
