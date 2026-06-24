import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stealth/p2p_service.dart';
import 'package:stealth/services/dashboard/dashboard_service.dart';
import 'package:stealth/services/device/device_info_service.dart';
import 'package:stealth/services/device/device_registry_service.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _isLoading = true;

  Map<String, dynamic> _dashboardStats = {};
  DeviceInfo? _deviceInfo;
  Map<String, dynamic> _p2pStats = {};
  int _installCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
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
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        _refresh();
      });
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      _dashboardStats = await DashboardService().getDashboardSummary();
      _deviceInfo = await DeviceInfoService.instance.getDeviceInfo();
      _p2pStats = P2PService.instance.getConnectionStats();
      _installCount = DeviceRegistryService.instance.installCount;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: TgAppBar(title: 'Мониторинг'),
      ),
      body: _isLoading
          ? Center(child: TgLoading.spinner())
          : ListView(
              padding: const EdgeInsets.all(TgSpacing.md),
              children: [
                _buildDashboardSection(),
                SizedBox(height: TgSpacing.md),
                _buildDeviceSection(),
                SizedBox(height: TgSpacing.md),
                _buildP2PSection(),
              ],
            ),
    );
  }

  Widget _buildDashboardSection() {
    return FlatContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TgSectionHeader(title: 'Статистика'),
          SizedBox(height: TgSpacing.sm),
          _buildStatRow('Чаты', '${_dashboardStats['chatCount'] ?? '-'}'),
          _buildStatRow(
              'Контакты', '${_dashboardStats['contactCount'] ?? '-'}'),
          _buildStatRow(
              'Сообщения', '${_dashboardStats['messageCount'] ?? '-'}'),
          _buildStatRow('Звонки', '${_dashboardStats['callCount'] ?? '-'}'),
        ],
      ),
    );
  }

  Widget _buildDeviceSection() {
    return FlatContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TgSectionHeader(title: 'Устройство'),
          SizedBox(height: TgSpacing.sm),
          _buildStatRow('Платформа', _deviceInfo?.platformType ?? '-'),
          _buildStatRow('ОС', _deviceInfo?.osVersion ?? '-'),
          _buildStatRow('Модель', _deviceInfo?.deviceModel ?? '-'),
          _buildStatRow('Бренд', _deviceInfo?.deviceBrand ?? '-'),
          _buildStatRow('Версия', _deviceInfo?.appVersion ?? '-'),
          _buildStatRow('Сборка', _deviceInfo?.appBuildNumber ?? '-'),
          _buildStatRow(
              'ID', _truncate(_dashboardStats['deviceId']?.toString() ?? '-')),
          _buildStatRow('Запусков', '$_installCount'),
        ],
      ),
    );
  }

  Widget _buildP2PSection() {
    return FlatContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TgSectionHeader(title: 'P2P / WebRTC'),
          SizedBox(height: TgSpacing.sm),
          _buildStatRow('Статус', '${_p2pStats['connectionSummary'] ?? '-'}'),
          _buildStatRow(
              'Подключения', '${_p2pStats['totalConnections'] ?? '-'}'),
          _buildStatRow('Каналы', '${_p2pStats['openDataChannels'] ?? '-'}'),
          _buildStatRow(
              'Переподключения', '${_p2pStats['reconnectCount'] ?? '-'}'),
          _buildStatRow('Посл. связь',
              (_p2pStats['lastConnectedAt']?.toString() ?? '').substring(0, 19)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TgTypography.footnote),
          Text(value, style: TgTypography.caption1),
        ],
      ),
    );
  }

  String _truncate(String value, [int max = 12]) {
    return value.length > max ? '${value.substring(0, max)}…' : value;
  }
}
