import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/services/app_metadata/app_metadata_service.dart';
import 'package:stealth/services/app_update/app_update_installer.dart';
import 'package:stealth/services/app_update/app_update_models.dart';
import 'package:stealth/services/app_update/app_update_service.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/ui/screens/app_update/update_status_card.dart';
import 'package:stealth/ui/screens/diagnostics/diagnostics_screen.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';
import 'package:stealth/webrtc_support.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.updateService,
    this.updateInstaller,
    this.metadataService = const AppMetadataService(),
    this.settingsLoader,
  });

  final AppUpdateService? updateService;
  final AppUpdateInstaller? updateInstaller;
  final AppMetadataService metadataService;
  final Future<SettingsSnapshot> Function()? settingsLoader;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalAppService _appService = LocalAppService();
  late final AppUpdateService _updateService;
  late final AppUpdateInstaller _updateInstaller;
  ThemeMode _themeMode = ThemeMode.system;
  bool _autoDeleteMessages = false;
  bool _contactVerification = true;
  bool _newMessageNotifications = true;
  bool _callNotifications = true;
  bool _useP2P = true;
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
  bool _isLoading = true;
  bool _isCheckingUpdate = false;
  bool _isInstallingUpdate = false;
  AppUpdateStatus? _updateStatus;
  AppUpdateInstallState? _installState;
  String _appVersionLabel = 'version unknown';

  @override
  void initState() {
    super.initState();
    _updateService = widget.updateService ?? AppUpdateService.fromEnv();
    _updateInstaller = widget.updateInstaller ?? AppUpdateInstaller();
    _loadSettings();
    _startPreviewTimer();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    final snapshot = widget.settingsLoader == null
        ? await _loadSettingsSnapshot()
        : await widget.settingsLoader!();
    final metadata = await widget.metadataService.load();
    final updateStatus =
        await _updateService.checkForUpdate(source: 'settings');
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = snapshot.themeMode;
      _useP2P = snapshot.useP2P;
      _messageCount = snapshot.messageCount;
      _callCount = snapshot.callCount;
      _chatCount = snapshot.chatCount;
      _bucketReady = snapshot.bucketReady;
      _webrtcSummary = snapshot.webrtcSummary;
      _webrtcPlatformLabel = snapshot.webrtcPlatformLabel;
      _webrtcAudioInputs = snapshot.webrtcAudioInputs;
      _appVersionLabel = metadata.displayVersion;
      _updateStatus = updateStatus;
      _diagnosticBars = [
        _chatCount == 0 ? 0.12 : (_chatCount.clamp(1, 10) / 10),
        _messageCount == 0 ? 0.12 : (_messageCount.clamp(1, 40) / 40),
        _callCount == 0 ? 0.12 : (_callCount.clamp(1, 10) / 10),
        snapshot.weeklyActivity
            .fold<double>(0.12, (max, value) => value > max ? value : max),
      ];
      _isLoading = false;
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

  Future<SettingsSnapshot> _loadSettingsSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final dashboard = await _appService.getDashboardSummary();
    final weeklyActivity = await _appService.getWeeklyActivityBars();
    final webrtcSupport = await getWebRTCSupport();
    return SettingsSnapshot(
      themeMode: ThemeMode.values[prefs.getInt('themeMode') ?? 2],
      useP2P: prefs.getBool('useP2P') ?? true,
      messageCount: dashboard['messageCount'] as int? ?? 0,
      callCount: dashboard['callCount'] as int? ?? 0,
      chatCount: dashboard['chatCount'] as int? ?? 0,
      bucketReady: dashboard['bucketReady'] as bool? ?? false,
      webrtcSummary: webrtcSupport.summary,
      webrtcPlatformLabel: webrtcSupport.platformLabel,
      webrtcAudioInputs: webrtcSupport.audioInputCount,
      weeklyActivity: weeklyActivity,
    );
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
    await _appService.logout();
    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegistrationScreen()),
      (route) => false,
    );
  }

  Future<void> _checkForUpdates() async {
    Logger.debug('[settings.ui] update check requested');
    setState(() {
      _isCheckingUpdate = true;
    });
    try {
      final status = await _updateService.checkForUpdate(source: 'settings');
      if (!mounted) {
        return;
      }
      Logger.info('[settings.ui] update status displayed', extras: {
        'status': status.kind.name,
      });
      setState(() {
        _updateStatus = status;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
      }
    }
  }

  Future<void> _installUpdateFromSettings() async {
    final manifest = _updateStatus?.manifest;
    if (manifest == null || !_updateStatus!.isUpdateAvailable) {
      Logger.warn('[settings.ui] update unavailable or unsupported', extras: {
        'reason': _updateStatus?.kind.name ?? 'missingStatus',
      });
      return;
    }
    Logger.info('[settings.ui] update install requested');
    setState(() {
      _isInstallingUpdate = true;
      _installState = const AppUpdateInstallState(
        phase: AppUpdateInstallPhase.idle,
      );
    });
    try {
      await _updateInstaller.installUpdate(
        manifest,
        onState: (state) {
          if (!mounted) {
            return;
          }
          setState(() {
            _installState = state;
          });
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isInstallingUpdate = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _buildSecurityCard(),
      _buildConnectionCard(),
      _buildNotificationCard(),
      _buildAppearanceCard(),
      _buildUpdatesCard(),
      _buildDiagnosticsCard(),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(title: 'Settings'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.systemBlue,
              ),
            )
          : Padding(
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

  Widget _buildConnectionCard() {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connection & Storage', style: AppTypography.headline),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            value: _useP2P,
            onChanged: (value) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('useP2P', value);
              setState(() => _useP2P = value);
            },
            title: const Text('Direct P2P messaging'),
            subtitle:
                const Text('Send messages directly to devices when online'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Local-only storage active',
            style: AppTypography.body.copyWith(
              color: AppColors.systemGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _SignalServerLine(),
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
              Expanded(
                  child: _MiniStat(label: 'Messages', value: '$_messageCount')),
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

  Widget _buildUpdatesCard() {
    return UpdateStatusCard(
      appVersionLabel: _appVersionLabel,
      status: _updateStatus,
      installState: _installState,
      isCheckingUpdate: _isCheckingUpdate,
      isInstallingUpdate: _isInstallingUpdate,
      onCheckForUpdates: _checkForUpdates,
      onInstallUpdate: _installUpdateFromSettings,
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
                  label: 'Local media',
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
            onPressed: () {
              Logger.debug('[settings.ui] navigate to diagnostics');
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiagnosticsScreen(
                    diagnosticsFactory: _appService.createDiagnostics,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bug_report),
            label: const Text('Open diagnostics & logs'),
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

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.themeMode,
    required this.useP2P,
    required this.messageCount,
    required this.callCount,
    required this.chatCount,
    required this.bucketReady,
    required this.webrtcSummary,
    required this.webrtcPlatformLabel,
    required this.webrtcAudioInputs,
    required this.weeklyActivity,
  });

  final ThemeMode themeMode;
  final bool useP2P;
  final int messageCount;
  final int callCount;
  final int chatCount;
  final bool bucketReady;
  final String webrtcSummary;
  final String webrtcPlatformLabel;
  final int webrtcAudioInputs;
  final List<double> weeklyActivity;
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

/// Read-only display of the PocketBase signal server URL from `.env`.
///
/// Runtime override is intentionally out of scope for this iteration — the
/// URL is configured at build time via `client/.env` (`POCKETBASE_URL`).
class _SignalServerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final url = _safePocketbaseUrl();
    final hasUrl = url.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.dns, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Signal server',
                style: AppTypography.caption1.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                hasUrl ? url : 'not configured (set POCKETBASE_URL in .env)',
                style: AppTypography.body.copyWith(
                  color:
                      hasUrl ? AppColors.systemGreen : AppColors.systemOrange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _safePocketbaseUrl() {
    try {
      return dotenv.maybeGet('POCKETBASE_URL') ?? '';
    } catch (_) {
      return '';
    }
  }
}
