import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stealth/registration_screen.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_haptics.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_loading_indicator.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/section_header.dart';
import 'package:stealth/themes/theme_controller.dart';
import 'package:stealth/services/bypass/bypass_state_controller.dart';
import 'package:stealth/ui/screens/diagnostics/diagnostics_screen.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';
import 'package:stealth/webrtc_support.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final LocalAppService _appService = LocalAppService();
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
  bool _bypassEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _startPreviewTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _previewTimer?.cancel();
    } else if (state == AppLifecycleState.resumed && _previewTimer == null) {
      _startPreviewTimer();
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final dashboard = await _appService.getDashboardSummary();
    final weeklyActivity = await _appService.getWeeklyActivityBars();
    final webrtcSupport = await getWebRTCSupport();
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = _themeModeFromIndex(prefs.getInt('themeMode'));
      _useP2P = prefs.getBool('useP2P') ?? true;
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
        weeklyActivity.fold<double>(
            0.12, (max, value) => value > max ? value : max),
      ];
      _bypassEnabled = BypassStateController.isEnabled;
      _isLoading = false;
    });
  }

  ThemeMode _themeModeFromIndex(int? index) {
    if (index == null || index < 0 || index >= ThemeMode.values.length) {
      return ThemeMode.system;
    }
    return ThemeMode.values[index];
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    // Push the new value through the shared ThemeController — that
    // (a) persists to SharedPreferences and (b) notifies the
    // ValueListenableBuilder around `MaterialApp`, so the theme
    // applies immediately without a restart.
    await ThemeController.setMode(mode);
    if (mounted) {
      StealthHaptics.selection(context);
    }
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
    await _appService.logout();
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
      RepaintBoundary(child: _buildSecurityCard()),
      RepaintBoundary(child: _buildConnectionCard()),
      RepaintBoundary(child: _buildNotificationCard()),
      RepaintBoundary(child: _buildAppearanceCard()),
      RepaintBoundary(child: _buildDiagnosticsCard()),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(title: 'Настройки'),
      ),
      body: _isLoading
          ? const Center(child: StealthLoadingIndicator())
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
            label: const Text('Выйти'),
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
          const SectionHeader(
            title: 'Конфиденциальность и безопасность',
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          SwitchListTile.adaptive(
            value: true,
            onChanged: null,
            title: const Text('Сквозное шифрование'),
            subtitle: const Text('Всегда включено для личных чатов'),
          ),
          SwitchListTile.adaptive(
            value: _autoDeleteMessages,
            onChanged: (value) => setState(() => _autoDeleteMessages = value),
            title: const Text('Предпросмотр автоудаления'),
          ),
          SwitchListTile.adaptive(
            value: _contactVerification,
            onChanged: (value) => setState(() => _contactVerification = value),
            title: const Text('Проверка контактов'),
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: _countdown / 24,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Таймер предпросмотра: ${_countdown}с',
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
          const SectionHeader(
            title: 'Подключение и Хранилище',
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          SwitchListTile.adaptive(
            value: _useP2P,
            onChanged: (value) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('useP2P', value);
              setState(() => _useP2P = value);
            },
            title: const Text('Прямые P2P сообщения'),
            subtitle:
                const Text('Отправляйте сообщения напрямую на устройства, когда они онлайн'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Активно только локальное хранилище',
            style: AppTypography.body.copyWith(
              color: AppColors.systemGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _SignalServerLine(),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            value: _bypassEnabled,
            onChanged: (value) async {
              if (value) {
                final ok = await BypassStateController.enable();
                if (mounted) setState(() => _bypassEnabled = ok);
              } else {
                await BypassStateController.disable();
                if (mounted) setState(() => _bypassEnabled = false);
              }
            },
            title: const Text('Обход цензуры'),
            subtitle: Text(
              _bypassEnabled ? 'Прокси активен — трафик через sing-box' : 'Прямое подключение',
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
          const SectionHeader(
            title: 'Уведомления',
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          SwitchListTile.adaptive(
            value: _newMessageNotifications,
            onChanged: (value) =>
                setState(() => _newMessageNotifications = value),
            title: const Text('Новые сообщения'),
          ),
          SwitchListTile.adaptive(
            value: _callNotifications,
            onChanged: (value) => setState(() => _callNotifications = value),
            title: const Text('Звонки'),
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
                  child: _MiniStat(label: 'Сообщения', value: '$_messageCount')),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: _MiniStat(label: 'Звонки', value: '$_callCount')),
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
          const SectionHeader(
            title: 'Оформление',
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
              ButtonSegment(value: ThemeMode.system, label: Text('Матч ОС')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Темная')),
            ],
            selected: {_themeMode},
            onSelectionChanged: (selection) => _changeTheme(selection.first),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Текущий режим: ${_themeMode.name == 'system' ? 'Матч ОС' : _themeMode.name == 'dark' ? 'Темная' : 'Светлая'}',
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
          const SectionHeader(
            title: 'Диагностика',
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
          ),
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
              Expanded(child: _MiniStat(label: 'Чаты', value: '$_chatCount')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MiniStat(
                  label: 'Локальные медиа',
                  value: _bucketReady ? 'Готово' : 'Проверить',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MiniStat(
                  label: 'Аудиовходы',
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
            label: const Text('Открыть диагностику WebRTC'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _loadSettings,
            icon: const Icon(Icons.refresh),
            label: const Text('Обновить диагностику'),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiagnosticsScreen(
                    diagnosticsFactory: _appService.createDiagnostics,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bug_report),
            label: const Text('Открыть диагностику и логи'),
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

/// Read-only display of the PocketBase signal server URL from `.env`.
///
/// Runtime override is intentionally out of scope for this iteration — the
/// URL is configured at build time via `client/.env` (`POCKETBASE_URL`).
class _SignalServerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final url = dotenv.maybeGet('POCKETBASE_URL') ?? '';
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
                'Сигнальный сервер',
                style: AppTypography.caption1.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                hasUrl ? url : 'не настроено (установите POCKETBASE_URL в .env)',
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
}
