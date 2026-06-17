import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_loading_indicator.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_snack_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/constants/accessibility_ids.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final LocalAppService _appService = LocalAppService();
  final TextEditingController _nicknameController = TextEditingController();
  String? _userId;
  String? _contactBundle;
  String? _nickname;
  bool _bucketReady = false;
  int _storageFileCount = 0;
  List<Map<String, dynamic>> _recentCalls = const [];
  List<double> _activityBars = const [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12];
  int _chatCount = 0;
  int _contactCount = 0;
  int _messageCount = 0;
  int _callCount = 0;
  bool _secureStorageReady = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      Logger.debug('[Profile] loading userId');
      final userId = await _appService.getUserId();
      Logger.debug('[Profile] user loaded', extras: {'userId': userId});
      final contactBundle = await _appService.generateQRCode();

      Logger.debug('[Profile] loading nickname');
      final nickname = await _appService.getNickname();
      Logger.debug('[Profile] nickname loaded');

      Logger.debug('[Profile] loading storageSummary');
      final storageSummary = await _appService.getStorageDebugSummary();
      Logger.debug('[Profile] storageSummary loaded', extras: storageSummary);
      if (contactBundle != null && contactBundle.isNotEmpty) {
        Logger.info('[Profile] CONTACT_BUNDLE for E2E test', extras: {'bundle': contactBundle});
        print('E2E_TEST_CONTACT_BUNDLE=$contactBundle');
      }

      Logger.debug('[Profile] loading recentCalls');
      final recentCalls = await _appService.getRecentCallHistory();
      Logger.debug('[Profile] recentCalls loaded', extras: {
        'count': recentCalls.length,
      });

      Logger.debug('[Profile] loading dashboard');
      final dashboard = await _appService.getDashboardSummary();
      Logger.debug('[Profile] dashboard loaded', extras: dashboard);

      Logger.debug('[Profile] loading weeklyActivity');
      final weeklyActivity = await _appService.getWeeklyActivityBars();
      Logger.debug('[Profile] weeklyActivity loaded');

      if (!mounted) return;

      setState(() {
        _userId = userId;
        _contactBundle = contactBundle;
        _nickname = nickname;
        _nicknameController.text = nickname ?? '';
        _bucketReady = storageSummary['bucketReady'] as bool? ?? false;
        _storageFileCount = storageSummary['fileCount'] as int? ?? 0;
        _recentCalls = recentCalls;
        _activityBars = weeklyActivity;
        _chatCount = dashboard['chatCount'] as int? ?? 0;
        _contactCount = dashboard['contactCount'] as int? ?? 0;
        _messageCount = dashboard['messageCount'] as int? ?? 0;
        _callCount = dashboard['callCount'] as int? ?? 0;
        _secureStorageReady = dashboard['secureStorageReady'] as bool? ?? false;
      });
    } catch (e, st) {
      Logger.error('[Profile] error loading profile', extras: {'error': e});
      Logger.debug('[Profile] stack trace', extras: {'stackTrace': st});
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _copyContactBundle() async {
    final value = _contactBundle ?? _userId;
    if (value == null || value.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }

    showStealthSnackBar(
      context,
      'Контакт скопирован',
      kind: SnackKind.success,
    );
  }

  Future<void> _logout() async {
    await _appService.logout();
    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegistrationScreen()),
      (route) => false,
    );
  }

  Future<void> _saveNickname() async {
    final value = _nicknameController.text.trim();
    if (value.isEmpty || value == _nickname) {
      return;
    }

    await _appService.updateNickname(value);
    if (!mounted) {
      return;
    }

    setState(() {
      _nickname = value;
    });
    showStealthSnackBar(
      context,
      'Никнейм обновлен',
      kind: SnackKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    Logger.debug(
      '[Profile] build',
      extras: {'isLoading': _isLoading, 'userId': _userId},
    );

    if (_isLoading) {
      return const Center(child: StealthLoadingIndicator());
    }

    if (_userId == null || _userId!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Не удалось загрузить профиль',
                style: AppTypography.headline.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Отсутствует ID пользователя. Проверьте логи или повторите попытку.',
                style:
                    AppTypography.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    // Design-system v2: asymmetric card grid. Hero IdentityCard
    // spans full width; Security+Activity sit side-by-side in a
    // 2-column row below; Storage + CallHistory return to full
    // width. Narrow viewports (< 600 px) collapse the 2-col row
    // back to a vertical stack so the layout still reads.
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Semantics(
        label: AccessibilityIds.logout,
        button: true,
        child: FloatingActionButton.extended(
          onPressed: _logout,
          backgroundColor: AppColors.statusDanger,
          foregroundColor: AppColors.textOnGlass,
          icon: const Icon(Icons.logout),
          label: const Text('Выйти'),
        ),
      ),
      body: Column(
        children: [
          const GlassAppBar(title: 'Профиль'),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 600;
                final securityActivityRow = isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildSecurityCard()),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: _buildActivityCard()),
                        ],
                      )
                    : Column(
                        children: [
                          _buildSecurityCard(),
                          const SizedBox(height: AppSpacing.md),
                          _buildActivityCard(),
                        ],
                      );
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.bottomBarOverlap,
                  ),
                  children: [
                    RepaintBoundary(child: _buildIdentityCard()),
                    const SizedBox(height: AppSpacing.md),
                    RepaintBoundary(child: securityActivityRow),
                    const SizedBox(height: AppSpacing.md),
                    RepaintBoundary(child: _buildStorageCard()),
                    const SizedBox(height: AppSpacing.md),
                    RepaintBoundary(child: _buildCallHistoryCard()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Идентификация', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          if (_userId != null && _userId!.isNotEmpty)
            Center(
              child: QrImageView(
                data: _contactBundle ?? _userId!,
                size: 180,
                version: QrVersions.auto,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.white,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            label: AccessibilityIds.username,
            child: TextField(
              controller: _nicknameController,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'Ваш никнейм',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _saveNickname(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: AccessibilityIds.userId,
            readOnly: true,
            child: Text(
              _userId ?? 'Загрузка профиля',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.caption1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: AccessibilityIds.copyContactBundle,
                  button: true,
                  child: FilledButton.icon(
                    onPressed: _copyContactBundle,
                    icon: const Icon(Icons.copy),
                    label: const Text('Скопировать контакт'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saveNickname,
                  icon: const Icon(Icons.save),
                  label: const Text('Сохранить алиас'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    final readinessScore = [
          _userId != null && _userId!.isNotEmpty,
          _secureStorageReady,
          _bucketReady,
          _messageCount > 0,
        ].where((value) => value).length /
        4;

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Безопасность', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: readinessScore,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${(readinessScore * 100).round()}% настроено',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildMetricRow('E2E ключи', _secureStorageReady ? 'Готово' : 'Отсутствуют'),
          _buildMetricRow('Безопасное хранилище',
              _secureStorageReady ? 'Включено' : 'Проверьте устройство'),
          _buildMetricRow(
              'Локальные медиа', _bucketReady ? 'Готово' : 'Отсутствуют'),
          _buildMetricRow(
            'Данные контакта',
            _contactBundle?.isNotEmpty == true ? 'Доступны' : 'Отсутствуют',
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            label: AccessibilityIds.copyContactBundle,
            button: true,
            child: OutlinedButton.icon(
              onPressed: _copyContactBundle,
              icon: const Icon(Icons.copy),
              label: const Text('Скопировать данные контакта'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    const labels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Недельная активность', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_activityBars.length, (index) {
                final value = _activityBars[index];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: 140 * value,
                              decoration: BoxDecoration(
                                color: AppColors.systemBlue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(labels[index], style: AppTypography.caption2),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildMiniKpi('Чаты', _chatCount.toString()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMiniKpi('Контакты', _contactCount.toString()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMiniKpi('Сообщения', _messageCount.toString()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMiniKpi('Звонки', _callCount.toString()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Отладка хранилища', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          _buildMetricRow('Локальные медиа', _bucketReady ? 'Готово' : 'Отсутствуют'),
          _buildMetricRow('Файлы', _storageFileCount.toString()),
          _buildMetricRow(
              'Платформа', kIsWeb ? 'веб' : Platform.operatingSystem),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: _bucketReady ? 1 : 0.25,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
            color:
                _bucketReady ? AppColors.systemGreen : AppColors.systemOrange,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Эта карточка проверяет зашифрованное локальное хранилище вложений.',
            style: AppTypography.caption1.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _loadProfile,
            icon: const Icon(Icons.sync),
            label: const Text('Обновить данные'),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Недавние звонки', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          if (_recentCalls.isEmpty)
            SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  'Пока нет записанных звонков.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: ListView.separated(
                itemCount: _recentCalls.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final call = _recentCalls[index];
                  final startedAt = DateTime.tryParse(
                    call['started_at'] as String? ?? '',
                  );
                  final durationSeconds = call['duration_seconds'] as int? ?? 0;
                  final isOutgoing = call['is_outgoing'] as bool? ?? false;
                  final peerName = call['peer_name'] as String? ?? 'Неизвестный';
                  final status = call['status'] as String? ?? 'неизвестно';

                  // Compact call history tile for both web and mobile layouts.
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOutgoing ? Icons.north_east : Icons.south_west,
                          color: isOutgoing
                              ? AppColors.systemBlue
                              : AppColors.systemGreen,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(peerName, style: AppTypography.body),
                              const SizedBox(height: 2),
                              Text(
                                '$status • ${_formatCallDuration(durationSeconds)}',
                                style: AppTypography.caption1.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          startedAt == null
                              ? '--:--'
                              : '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}',
                          style: AppTypography.caption2,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatCallDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: AppTypography.body)),
          Text(
            value,
            style: AppTypography.body.copyWith(
              color: AppColors.systemGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniKpi(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(value,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.caption2.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
