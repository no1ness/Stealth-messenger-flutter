import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
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
      debugPrint('[Profile] loading userId...');
      final userId = await _appService.getUserId();
      debugPrint('[Profile] userId=$userId');
      final contactBundle = await _appService.generateQRCode();

      debugPrint('[Profile] loading nickname...');
      final nickname = await _appService.getNickname();
      debugPrint('[Profile] nickname=$nickname');

      debugPrint('[Profile] loading storageSummary...');
      final storageSummary = await _appService.getStorageDebugSummary();
      debugPrint('[Profile] storageSummary=$storageSummary');

      debugPrint('[Profile] loading recentCalls...');
      final recentCalls = await _appService.getRecentCallHistory();
      debugPrint('[Profile] recentCalls len=${recentCalls.length}');

      debugPrint('[Profile] loading dashboard...');
      final dashboard = await _appService.getDashboardSummary();
      debugPrint('[Profile] dashboard=$dashboard');

      debugPrint('[Profile] loading weeklyActivity...');
      final weeklyActivity = await _appService.getWeeklyActivityBars();
      debugPrint('[Profile] weeklyActivity=$weeklyActivity');

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
      debugPrint('[Profile] Error loading profile: $e');
      debugPrint('[Profile] $st');
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact bundle copied')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nickname updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('ProfileScreen: build called, _isLoading=$_isLoading, _userId=$_userId');

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.systemBlue,
        ),
      );
    }

    if (_userId == null || _userId!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Unable to load profile',
                style: AppTypography.headline.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'User ID is missing. Check logs or retry.',
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final cards = [
      _buildIdentityCard(),
      _buildSecurityCard(),
      _buildActivityCard(),
      _buildStorageCard(),
      _buildCallHistoryCard(),
    ];

    return Stack(
      children: [
        Column(
          children: [
            const GlassAppBar(title: 'Profile'),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: cards.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) => cards[index],
              ),
            ),
            const SizedBox(height: 80), // Space for bottom bar
          ],
        ),
        Positioned(
          right: AppSpacing.md,
          bottom: 100,
          child: Semantics(
            label: AccessibilityIds.logout,
            button: true,
            child: FloatingActionButton.extended(
              onPressed: _logout,
              backgroundColor: AppColors.systemRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Identity', style: AppTypography.headline),
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
                hintText: 'Your nickname',
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
              _userId ?? 'Loading profile',
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
                    label: const Text('Copy contact'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saveNickname,
                  icon: const Icon(Icons.save),
                  label: const Text('Save alias'),
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
    ].where((value) => value).length / 4;

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Security posture', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: readinessScore,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${(readinessScore * 100).round()}% configured',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildMetricRow('E2E keypair', _secureStorageReady ? 'Ready' : 'Missing'),
          _buildMetricRow('Secure storage', _secureStorageReady ? 'Enabled' : 'Check device'),
          _buildMetricRow('Local media store', _bucketReady ? 'Ready' : 'Missing'),
          _buildMetricRow(
            'Contact bundle',
            _contactBundle?.isNotEmpty == true ? 'Available' : 'Missing',
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            label: AccessibilityIds.copyContactBundle,
            button: true,
            child: OutlinedButton.icon(
              onPressed: _copyContactBundle,
              icon: const Icon(Icons.copy),
              label: const Text('Copy contact bundle'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Weekly activity', style: AppTypography.headline),
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
                child: _buildMiniKpi('Chats', _chatCount.toString()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMiniKpi('Contacts', _contactCount.toString()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMiniKpi('Messages', _messageCount.toString()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildMiniKpi('Calls', _callCount.toString()),
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
          Text('Storage debug', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          _buildMetricRow('Local media', _bucketReady ? 'Ready' : 'Missing'),
          _buildMetricRow('Files', _storageFileCount.toString()),
          _buildMetricRow('Platform', kIsWeb ? 'web' : Platform.operatingSystem),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: _bucketReady ? 1 : 0.25,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
            color: _bucketReady ? AppColors.systemGreen : AppColors.systemOrange,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'This card verifies encrypted local attachment storage.',
            style: AppTypography.caption1.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _loadProfile,
            icon: const Icon(Icons.sync),
            label: const Text('Refresh debug'),
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
          Text('Recent calls', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          if (_recentCalls.isEmpty)
            SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  'No calls recorded yet.',
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
                  final durationSeconds =
                      call['duration_seconds'] as int? ?? 0;
                  final isOutgoing = call['is_outgoing'] as bool? ?? false;
                  final peerName =
                      call['peer_name'] as String? ?? 'Unknown';
                  final status = call['status'] as String? ?? 'unknown';

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
          Text(label, style: AppTypography.body),
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
          Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w700)),
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
