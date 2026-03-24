import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';
import 'package:stealth/webrtc_support.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  ThemeMode _themeMode = ThemeMode.system;
  bool _autoDeleteMessages = false;
  bool _contactVerification = true;
  bool _newMessageNotifications = true;
  bool _callNotifications = true;
  Timer? _previewTimer;
  int _countdown = 24;
  int _messageCount = 0;
  int _callCount = 0;
  int _chatCount = 0;
  bool _bucketReady = false;
  String _webrtcSummary = 'Checking...';
  String _webrtcPlatformLabel = 'Checking...';
  int _webrtcAudioInputs = 0;
  List<double> _diagnosticBars = const [0.12, 0.12, 0.12, 0.12];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startPreviewTimer();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final dashboard = await _supabaseService.getDashboardSummary();
    final weeklyActivity = await _supabaseService.getWeeklyActivityBars();
    final webrtcSupport = await getWebRTCSupport();
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? 2];
      _messageCount = dashboard['messageCount'] as int? ?? 0;
      _callCount = dashboard['callCount'] as int? ?? 0;
      _chatCount = dashboard['chatCount'] as int? ?? 0;
      _bucketReady = dashboard['bucketReady'] as bool? ?? false;
      _webrtcSummary = webrtcSupport.summary;
      _webrtcPlatformLabel = webrtcSupport.platformLabel;
      _webrtcAudioInputs = webrtcSupport.audioInputCount;
      _diagnosticBars = [
        _chatCount == 0 ? 0.12 : (_chatCount.clamp(1, 10) / 10),
        _messageCount == 0 ? 0.12 : (_messageCount.clamp(1, 40) / 40),
        _callCount == 0 ? 0.12 : (_callCount.clamp(1, 10) / 10),
        weeklyActivity.fold<double>(0.12, (max, value) => value > max ? value : max),
      ];
    });
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = mode;
    });
  }

  void _startPreviewTimer() {
    // This timer is only a UX preview for ephemeral messages.
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _countdown = _countdown == 0 ? 24 : _countdown - 1;
      });
    });
  }

  Future<void> _logout() async {
    await _supabaseService.logout();
    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegistrationScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _buildSecurityCard(),
      _buildNotificationCard(),
      _buildAppearanceCard(),
      _buildDiagnosticsCard(),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(title: 'Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1100) {
              return GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.4,
                children: cards,
              );
            }

            return ListView.separated(
              itemCount: cards.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) => cards[index],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Privacy & security', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            value: true,
            onChanged: null,
            title: const Text('End-to-end encryption'),
            subtitle: const Text('Always enabled for private chats'),
          ),
          SwitchListTile.adaptive(
            value: _autoDeleteMessages,
            onChanged: (value) => setState(() => _autoDeleteMessages = value),
            title: const Text('Auto-delete preview'),
          ),
          SwitchListTile.adaptive(
            value: _contactVerification,
            onChanged: (value) => setState(() => _contactVerification = value),
            title: const Text('Contact verification'),
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: _countdown / 24,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Preview timer: ${_countdown}s',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Notifications', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            value: _newMessageNotifications,
            onChanged: (value) =>
                setState(() => _newMessageNotifications = value),
            title: const Text('New messages'),
          ),
          SwitchListTile.adaptive(
            value: _callNotifications,
            onChanged: (value) => setState(() => _callNotifications = value),
            title: const Text('Calls'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _webrtcSummary,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _webrtcPlatformLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption1.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Messages', value: '$_messageCount')),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: _MiniStat(label: 'Calls', value: '$_callCount')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Appearance', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {_themeMode},
            onSelectionChanged: (selection) => _changeTheme(selection.first),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Current mode: ${_themeMode.name}',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Diagnostics', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _diagnosticBars
                  .map(
                    (value) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.systemBlue.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SizedBox(height: 100 * value),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Chats', value: '$_chatCount')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MiniStat(
                  label: 'Media bucket',
                  value: _bucketReady ? 'Ready' : 'Check',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MiniStat(
                  label: 'Audio inputs',
                  value: '$_webrtcAudioInputs',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WebRTCDiagnosticsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.network_check),
            label: const Text('Open WebRTC diagnostics'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _loadSettings,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh diagnostics'),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
}
