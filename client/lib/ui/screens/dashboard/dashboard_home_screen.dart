import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stealth/services/monitoring/monitoring_data_service.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_loading_indicator.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_container.dart';
import 'package:stealth/themes/apple_liquid/widgets/section_header.dart';

class DashboardHomeScreen extends StatefulWidget {
  const DashboardHomeScreen({super.key});

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen>
    with WidgetsBindingObserver {
  final MonitoringDataService _dataService = MonitoringDataService();
  Timer? _refreshTimer;
  bool _isLoading = true;

  Map<String, dynamic> _aggregated = {};
  Map<String, int> _platformBreakdown = {};
  List<Map<String, dynamic>> _recentRecords = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed && _refreshTimer == null) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted) return;
        _refresh();
      });
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      _aggregated = await _dataService.getAggregated();
      _platformBreakdown = await _dataService.getPlatformBreakdown();
      _recentRecords = (await _dataService.getAllStats())
          .take(20)
          .toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Дашборд'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: StealthLoadingIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _buildOverviewSection(),
                  const SizedBox(height: AppSpacing.md),
                  _buildPlatformSection(),
                  const SizedBox(height: AppSpacing.md),
                  _buildRecentRecordsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildOverviewSection() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Обзор'),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _buildStatCard('Пользователи', '${_aggregated['totalUsers'] ?? '-'}')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _buildStatCard('Чаты', '${_aggregated['totalChats'] ?? '-'}')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _buildStatCard('Сообщения', '${_aggregated['totalMessages'] ?? '-'}')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _buildStatCard('Звонки', '${_aggregated['totalCalls'] ?? '-'}')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildStatCard('Контакты', '${_aggregated['totalContacts'] ?? '-'}'),
        ],
      ),
    );
  }

  Widget _buildPlatformSection() {
    final entries = _platformBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Платформы'),
          const SizedBox(height: AppSpacing.sm),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Text('Нет данных'),
            )
          else
            ...entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key, style: AppTypography.footnote),
                  Text('${e.value}', style: AppTypography.caption1),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildRecentRecordsSection() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Последние события'),
          const SizedBox(height: AppSpacing.sm),
          if (_recentRecords.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Text('Пока нет записей'),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  children: [
                    Text('Пользователь', style: AppTypography.caption1.copyWith(fontWeight: FontWeight.bold)),
                    Text('Платформа', style: AppTypography.caption1.copyWith(fontWeight: FontWeight.bold)),
                    Text('Сообщ', style: AppTypography.caption1.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                ..._recentRecords.map((r) => TableRow(
                  children: [
                    Text(_truncate(r['userId']?.toString() ?? '-', 8), style: AppTypography.footnote),
                    Text(r['platformType']?.toString() ?? '-', style: AppTypography.footnote),
                    Text('${r['messageCount'] ?? '-'}', style: AppTypography.footnote),
                  ],
                )),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.glassLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Text(value, style: AppTypography.title2),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.caption1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _truncate(String value, [int max = 12]) {
    return value.length > max ? '${value.substring(0, max)}\u2026' : value;
  }
}
