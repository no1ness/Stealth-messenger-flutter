import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/ui/widgets/empty_state.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final LocalAppService _appService = LocalAppService();
  List<Map<String, dynamic>> _calls = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCalls();
  }

  Future<void> _loadCalls() async {
    try {
      final calls = await _appService.getRecentCallHistory(limit: 50);
      if (mounted) {
        setState(() {
          _calls = calls;
          _loading = false;
        });
      }
    } catch (e) {
      Logger.error('[calls] failed to load call history', extras: {'error': e});
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const GlassAppBar(
        isLargeTitle: true,
        title: 'Звонки',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _calls.isEmpty
              ? const StealthEmptyState.calls()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    AppSpacing.sm,
                    0,
                    MediaQuery.of(context).padding.bottom +
                        AppSpacing.bottomBarOverlap,
                  ),
                  itemCount: _calls.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.xxs),
                  itemBuilder: (context, index) {
                    final call = _calls[index];
                    return _buildCallTile(call);
                  },
                ),
    );
  }

  Widget _buildCallTile(Map<String, dynamic> call) {
    final direction = call['direction'] as String? ?? 'local';
    final status = call['status'] as String? ?? 'ended';
    final peerName = call['peer_nickname'] as String? ??
        call['peer_user_id'] as String? ??
        'Неизвестно';
    final startedAt = call['started_at'] as String? ?? '';
    final isIncoming = direction == 'incoming';
    final isMissed = isIncoming && status == 'declined';
    final isOutgoing = direction == 'local';

    IconData icon;
    Color iconColor;
    if (isMissed) {
      icon = Icons.call_missed;
      iconColor = AppColors.systemRed;
    } else if (isIncoming) {
      icon = Icons.call_received;
      iconColor = AppColors.systemGreen;
    } else {
      icon = Icons.call_made;
      iconColor = AppColors.systemBlue;
    }

    final dateStr = startedAt.isNotEmpty
        ? _formatCallDate(DateTime.tryParse(startedAt))
        : '';

    return ListTile(
      leading: Icon(icon, color: iconColor, size: AppSpacing.iconMd),
      title: Text(
        peerName,
        style: AppTypography.bodyEmphasis.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        dateStr,
        style: AppTypography.caption1.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      onTap: () {},
    );
  }

  String _formatCallDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(date.year, date.month, date.day);
    final diffDays = today.difference(thatDay).inDays;

    if (diffDays == 0) {
      return 'Сегодня, ${DateFormat('HH:mm').format(date)}';
    }
    if (diffDays == 1) {
      return 'Вчера, ${DateFormat('HH:mm').format(date)}';
    }
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }
}
