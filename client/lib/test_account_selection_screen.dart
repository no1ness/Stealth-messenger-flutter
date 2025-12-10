import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/widgets/circuit_board_background.dart';

/// Экран выбора тестового аккаунта для удобного тестирования
class TestAccountSelectionScreen extends StatefulWidget {
  const TestAccountSelectionScreen({super.key});

  @override
  State<TestAccountSelectionScreen> createState() => _TestAccountSelectionScreenState();
}

class _TestAccountSelectionScreenState extends State<TestAccountSelectionScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = false;
  String? _loadingAccount;

  // Фиксированные UUID для тестовых пользователей
  static const String pocoUserId = '11111111-1111-1111-1111-111111111111';
  static const String geekomUserId = '22222222-2222-2222-2222-222222222222';

  Future<void> _loginAsTestAccount(String userId, String nickname) async {
    setState(() {
      _isLoading = true;
      _loadingAccount = nickname;
    });

    try {
      // Логинимся с фиксированным ID
      await _supabaseService.loginAsTestUser(userId: userId, nickname: nickname);
      
      if (!mounted) return;
      
      // Переходим на главный экран
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainTabs()),
      );
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
        _loadingAccount = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка входа: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CircuitBoardBackground(
        animated: true,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Логотип/заголовок
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.security,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'STEALTH',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Тестовый режим',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  const Text(
                    'Выберите аккаунт для тестирования:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Кнопка POCO
                  _buildAccountButton(
                    name: 'POCO',
                    subtitle: 'UUID: $pocoUserId',
                    icon: Icons.smartphone,
                    color: Colors.blue,
                    onPressed: _isLoading 
                        ? null 
                        : () => _loginAsTestAccount(pocoUserId, 'POCO'),
                    isLoading: _loadingAccount == 'POCO',
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Кнопка GEEKOM
                  _buildAccountButton(
                    name: 'GEEKOM',
                    subtitle: 'UUID: $geekomUserId',
                    icon: Icons.computer,
                    color: Colors.green,
                    onPressed: _isLoading 
                        ? null 
                        : () => _loginAsTestAccount(geekomUserId, 'GEEKOM'),
                    isLoading: _loadingAccount == 'GEEKOM',
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Подсказка
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Как добавить контакты:',
                                style: TextStyle(
                                  color: Colors.orange[200],
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Text(
                            '1. Войдите в разные аккаунты\n'
                            '2. Скопируйте UUID сверху\n'
                            '3. Добавьте друг друга в контактах',
                            style: TextStyle(
                              color: Colors.orange[100],
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountButton({
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required bool isLoading,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 100,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: color.withOpacity(0.5),
              width: 2,
            ),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? CircularProgressIndicator(color: color)
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 40, color: color),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: color.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: color),
                ],
              ),
      ),
    );
  }
}
