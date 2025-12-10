import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/test_account_selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _e2eEncryption = true; // Always enabled
  bool _autoDeleteMessages = false;
  bool _contactVerification = true;
  bool _newMessageNotifications = true;
  bool _callNotifications = true;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы вернетесь на экран выбора тестового аккаунта.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Выходим
    await _supabaseService.logout();

    if (!mounted) return;

    // Переходим на экран выбора аккаунта
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const TestAccountSelectionScreen(),
      ),
      (route) => false, // Удаляем все предыдущие маршруты
    );
  }

  Future<void> _loadSettings() async {
    // _autoDeleteMessages = await _supabaseService.getBoolSetting('autoDeleteMessages');
    // _contactVerification = await _supabaseService.getBoolSetting('contactVerification', defaultValue: true);
    // _newMessageNotifications = await _supabaseService.getBoolSetting('newMessageNotifications', defaultValue: true);
    // _callNotifications = await _supabaseService.getBoolSetting('callNotifications', defaultValue: true);
    
    // Загружаем сохраненную тему
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 2; // 2 = ThemeMode.system
    _themeMode = ThemeMode.values[themeIndex];
    
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _changeTheme(ThemeMode newTheme) async {
    _themeMode = newTheme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', newTheme.index);
    if (!mounted) return;
    setState(() {});
  }

  String _getThemeModeText() {
    switch (_themeMode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Информация о текущем аккаунте
            FutureBuilder<String?>(
              future: _supabaseService.getNickname(),
              builder: (context, snapshot) {
                final nickname = snapshot.data ?? 'Unknown';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Текущий аккаунт',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              nickname,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Configure your privacy and notification preferences',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Privacy & Security Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy & Security',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('End-to-End Encryption'),
                      subtitle: const Text('Always enabled for all messages'),
                      value: _e2eEncryption,
                      onChanged: (bool value) {
                        setState(() {
                          _e2eEncryption = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Auto-delete messages'),
                      subtitle: const Text('Automatically delete old messages'),
                      value: _autoDeleteMessages,
                      onChanged: (bool value) async {
                        // await _supabaseService.setBoolSetting('autoDeleteMessages', value);
                        setState(() {
                          _autoDeleteMessages = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Contact verification'),
                      subtitle: const Text('Verify new contacts before chatting'),
                      value: _contactVerification,
                      onChanged: (bool value) async {
                        // await _supabaseService.setBoolSetting('contactVerification', value);
                        setState(() {
                          _contactVerification = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Notifications Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('New message notifications'),
                      subtitle: const Text('Get notified of new messages'),
                      value: _newMessageNotifications,
                      onChanged: (bool value) async {
                        // await _supabaseService.setBoolSetting('newMessageNotifications', value);
                        setState(() {
                          _newMessageNotifications = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Call notifications'),
                      subtitle: const Text('Get notified of incoming calls'),
                      value: _callNotifications,
                      onChanged: (bool value) async {
                        // await _supabaseService.setBoolSetting('callNotifications', value);
                        setState(() {
                          _callNotifications = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Appearance Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('Theme'),
                      subtitle: Text(_getThemeModeText()),
                      trailing: PopupMenuButton<ThemeMode>(
                        onSelected: _changeTheme,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: ThemeMode.system,
                            child: Text('System default'),
                          ),
                          const PopupMenuItem(
                            value: ThemeMode.light,
                            child: Text('Light'),
                          ),
                          const PopupMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Dark'),
                          ),
                        ],
                        child: const Icon(Icons.arrow_forward_ios, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Diagnostics Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diagnostics',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('WebRTC Diagnostics'),
                      subtitle: const Text('Test voice calling functionality'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // Navigate to diagnostics screen
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => Scaffold(
                              appBar: AppBar(title: Text('WebRTC Diagnostics')),
                              body: Center(child: Text('WebRTC Diagnostics - Coming Soon')),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            
            // Кнопка выхода из аккаунта
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Выйти из аккаунта',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Подсказка
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Используйте выход для переключения между POCO и GEEKOM',
                      style: TextStyle(
                        color: Colors.orange[200],
                        fontSize: 12,
                      ),
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
}