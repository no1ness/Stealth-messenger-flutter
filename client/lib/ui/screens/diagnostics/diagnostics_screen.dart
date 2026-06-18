import 'package:flutter/material.dart';

import '../../../logging/log_buffer.dart';
import '../../../logging/logger.dart';
import '../../../services/diagnostics/app_environment_info.dart';
import '../../../services/diagnostics/diagnostics_report.dart';
import '../../../services/diagnostics/diagnostics_service.dart';
import '../../../services/diagnostics/diagnostics_share.dart';
import '../../../services/diagnostics/service_status.dart';
import '../../../themes/apple_liquid/components/glass_container.dart';
import '../../../themes/apple_liquid/constants/app_colors.dart';
import '../../../themes/apple_liquid/constants/app_spacing.dart';
import '../../../themes/apple_liquid/constants/app_typography.dart';
import '../../../themes/apple_liquid/widgets/glass_app_bar.dart';
import 'widgets/level_filter_chips.dart';
import 'widgets/log_entry_tile.dart';
import 'widgets/service_status_tile.dart';
import 'widgets/performance_monitor.dart';

/// Function used by [DiagnosticsScreen] to read the log buffer. Defaults
/// to `Logger.snapshot`; widget tests inject a fake to assert filter
/// behaviour without touching global state.
typedef LogProvider = List<LogEntry> Function({
  required LogLevel min,
  int? limit,
});

/// Async provider for the runtime environment snapshot used in the
/// report header. Defaults to `AppEnvironmentInfo.collect`; widget
/// tests inject a stub to avoid native-channel calls that never
/// complete in the unit test harness.
typedef EnvironmentProvider = Future<AppEnvironmentInfo> Function();

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    this.diagnostics,
    this.diagnosticsFactory,
    this.logProvider = Logger.snapshot,
    this.shareInvoker = shareDiagnosticsReport,
    this.envProvider = AppEnvironmentInfo.collect,
  }) : assert(
          diagnostics != null || diagnosticsFactory != null,
          'Either diagnostics or diagnosticsFactory must be provided',
        );

  /// Caller-owned service. Tests use this — screen does NOT call
  /// `dispose()` on it.
  final DiagnosticsService? diagnostics;

  /// Production path: screen state creates a fresh instance in
  /// `initState` and calls `dispose()` in state's `dispose()`.
  final DiagnosticsService Function()? diagnosticsFactory;

  final LogProvider logProvider;
  final ShareInvoker shareInvoker;
  final EnvironmentProvider envProvider;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final DiagnosticsService _diagnostics;
  late final bool _ownsDiagnostics;

  List<LogEntry> _logs = const [];
  LogLevel _filter = LogLevel.warn;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    if (widget.diagnostics != null) {
      _diagnostics = widget.diagnostics!;
      _ownsDiagnostics = false;
    } else {
      _diagnostics = widget.diagnosticsFactory!();
      _ownsDiagnostics = true;
    }
    _refreshLogs();
    Logger.debug('[diag.ui] screen opened');
  }

  @override
  void dispose() {
    if (_ownsDiagnostics) {
      _diagnostics.dispose();
      Logger.info('[diag.ui] owned diagnostics disposed');
    }
    super.dispose();
  }

  void _refreshLogs() {
    final next = widget.logProvider(min: _filter, limit: 200);
    setState(() => _logs = next);
    if (next.isEmpty) {
      Logger.warn('[diag.ui] log list empty for filter',
          extras: {'filter': _filter.name});
    }
  }

  void _onFilterChanged(LogLevel level) {
    if (_filter == level) return;
    Logger.debug('[diag.ui] filter changed', extras: {'level': level.name});
    setState(() => _filter = level);
    _refreshLogs();
  }

  Future<void> _onShare() async {
    if (_isSharing) return;
    Logger.info('[diag.ui] share button pressed');
    setState(() => _isSharing = true);
    try {
      final statuses =
          _diagnostics.lastKnownSnapshot ?? await _diagnostics.snapshot();
      final env = await widget.envProvider();
      // Pull the full buffer (all levels) for the export — recipients
      // typically want context around the WARN/ERROR window.
      final logs = Logger.snapshot(min: LogLevel.debug, limit: 500);
      final report = buildDiagnosticsReport(
        statuses: statuses,
        logs: logs,
        env: env,
      );
      if (!mounted) return;
      await widget.shareInvoker(context, report);
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Диагностика и логи',
        showBackButton: true,
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLogs,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  const _SectionHeader(title: 'Сервисы'),
                  SliverToBoxAdapter(
                    child: StreamBuilder<List<ServiceStatus>>(
                      initialData: _diagnostics.lastKnownSnapshot,
                      stream: _diagnostics.watch(),
                      builder: (context, snapshot) {
                        final statuses = snapshot.data ?? const [];
                        if (statuses.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(AppSpacing.md),
                            child: Text('Загрузка...'),
                          );
                        }
                        return Column(
                          children: [
                            for (final s in statuses)
                              ServiceStatusTile(status: s),
                          ],
                        );
                      },
                    ),
                  ),
                  const _SectionHeader(title: 'Производительность'),
                  const SliverToBoxAdapter(
                    child: PerformanceMonitor(),
                  ),
                  const _SectionHeader(title: 'Последние логи'),
                  SliverToBoxAdapter(
                    child: LevelFilterChips(
                      selected: _filter,
                      onSelected: _onFilterChanged,
                    ),
                  ),
                  if (_logs.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'Пока нет записей в логе',
                          style: AppTypography.body,
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => LogEntryTile(entry: _logs[i]),
                        childCount: _logs.length,
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.lg),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: GlassButton(
                  isPrimary: true,
                  onPressed: _isSharing ? null : _onShare,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSharing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.ios_share),
                      const SizedBox(width: AppSpacing.sm),
                      const Text('Поделиться логами'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Text(
          title,
          style: AppTypography.headline.copyWith(color: AppColors.systemGray),
        ),
      ),
    );
  }
}
