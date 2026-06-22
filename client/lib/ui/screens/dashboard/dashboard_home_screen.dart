import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stealth/services/monitoring/monitoring_data_service.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class DashboardHomeScreen extends StatefulWidget {
  const DashboardHomeScreen({super.key});

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen>
    with WidgetsBindingObserver {
  TgThemeColors get c => TgThemeColors.of(context);
  final MonitoringDataService _dataService = MonitoringDataService();
  Timer? _refreshTimer;
  bool _isLoading = true;
  DateTime? _lastUpdated;

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
      _recentRecords = (await _dataService.getAllStats()).take(20).toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _lastUpdated = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Scaffold(
      backgroundColor: Color(0xFF17212B),
      body: _isLoading
          ? Center(child: TgLoading.spinner())
          : RefreshIndicator(
              onRefresh: _refresh,
              color: Color(0xFF00C853),
              backgroundColor: Color(0xFF17212B),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  return CustomScrollView(
                    slivers: [
                      _buildAppBar(),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isWide ? 32 : 16,
                          vertical: 16,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildStatusBar(),
                            const SizedBox(height: 20),
                            _buildStatsGrid(constraints.maxWidth, isWide),
                            const SizedBox(height: 20),
                            _buildPlatformSection(),
                            const SizedBox(height: 20),
                            _buildRecentSection(),
                            const SizedBox(height: 32),
                          ]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  SliverToBoxAdapter _buildAppBar() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF17212B),
          border: Border(
            bottom: BorderSide(color: Color(0xFF3C4A57), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFF2AABEE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STEALTH Dashboard',
                    style: TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'System Monitor',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Color(0xFF00C853).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C853),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x6000C853),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF00C853),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    if (_lastUpdated == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.access_time, color: c.textSecondary),
        const SizedBox(width: 4),
        Text(
          'Updated ${_formatTime(_lastUpdated!)}',
          style: TextStyle(color: c.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(double containerWidth, bool isWide) {
    final stats = [
      _StatItem(
        'Users',
        '${_aggregated['totalUsers'] ?? 0}',
        Icons.people_outline,
        Color(0xFF2AABEE),
      ),
      _StatItem(
        'Chats',
        '${_aggregated['totalChats'] ?? 0}',
        Icons.chat_bubble_outline,
        Color(0xFF00C853),
      ),
      _StatItem(
        'Messages',
        '${_aggregated['totalMessages'] ?? 0}',
        Icons.mail_outline,
        const Color(0xFFFF9800),
      ),
      _StatItem(
        'Calls',
        '${_aggregated['totalCalls'] ?? 0}',
        Icons.call_outlined,
        const Color(0xFFE91E63),
      ),
      _StatItem(
        'Contacts',
        '${_aggregated['totalContacts'] ?? 0}',
        Icons.contacts_outlined,
        const Color(0xFF9C27B0),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats.map((s) {
        final width = isWide
            ? (containerWidth - 64) / 5 - 12
            : (containerWidth - 44) / 2 - 12;
        return SizedBox(
          width: width,
          child: _buildStatCard(s),
        );
      }).toList(),
    );
  }

  Widget _buildStatCard(_StatItem stat) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Color(0xFF242F3D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF3C4A57), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: stat.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(stat.icon, color: stat.color),
            ),
            const SizedBox(height: 14),
            Text(
              stat.value,
              style: const TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stat.label,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformSection() {
    final entries = _platformBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF242F3D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF3C4A57), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'Platforms',
              style: TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No data yet',
                style: TextStyle(color: c.textSecondary, fontSize: 14),
              ),
            )
          else
            ...entries.map((e) {
              final pct = total > 0 ? e.value / total : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _platformIcon(e.key),
                            const SizedBox(width: 8),
                            Text(
                              e.key,
                              style: const TextStyle(
                                color: Color(0xFFF5F5F5),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${e.value}',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Color(0xFF3C4A57),
                        valueColor: AlwaysStoppedAnimation(
                          _platformColor(e.key),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildRecentSection() {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF242F3D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF3C4A57), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'Recent Activity',
              style: TextStyle(
                color: Color(0xFFF5F5F5),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_recentRecords.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No records yet',
                style: TextStyle(color: c.textSecondary, fontSize: 14),
              ),
            )
          else
            ..._recentRecords.take(10).map((r) => _buildRecordRow(r)),
          if (_recentRecords.length > 10)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                  'and ${_recentRecords.length - 10} more...',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordRow(Map<String, dynamic> record) {
    final userId = record['userId']?.toString() ?? '-';
    final platform = record['platformType']?.toString() ?? '?';
    final messages = record['messageCount'] ?? 0;
    final calls = record['callCount'] ?? 0;
    final device = record['deviceModel']?.toString() ?? '';
    final version = record['appVersion']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4A57), width: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _platformColor(platform).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: _platformIcon(platform),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _truncate(userId, 12),
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [platform, device, version].where((s) => s.isNotEmpty).join(' \u00b7 '),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (messages > 0)
                _buildMiniStat(Icons.mail_outline, '$messages', const Color(0xFFFF9800)),
              if (calls > 0)
                _buildMiniStat(Icons.call_outlined, '$calls', const Color(0xFFE91E63)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _platformIcon(String platform, {double size = 16}) {
    final color = _platformColor(platform);
    IconData icon;
    switch (platform.toLowerCase()) {
      case 'android':
        icon = Icons.android;
        break;
      case 'ios':
        icon = Icons.apple;
        break;
      case 'web':
        icon = Icons.language;
        break;
      case 'windows':
        icon = Icons.desktop_windows;
        break;
      case 'macos':
        icon = Icons.laptop_mac;
        break;
      case 'linux':
        icon = Icons.computer;
        break;
      default:
        icon = Icons.device_unknown;
    }
    return Icon(icon, color: color);
  }

  Color _platformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return const Color(0xFF3DDC84);
      case 'ios':
        return const Color(0xFF007AFF);
      case 'web':
        return Color(0xFF00C853);
      case 'windows':
        return const Color(0xFF00A4EF);
      case 'macos':
        return const Color(0xFF8E8E93);
      case 'linux':
        return const Color(0xFFDD4814);
      default:
        return const Color(0xFF8E8E93);
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _truncate(String value, [int max = 12]) {
    return value.length > max ? '${value.substring(0, max)}\u2026' : value;
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem(this.label, this.value, this.icon, this.color);
}
