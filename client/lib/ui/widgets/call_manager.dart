import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';

/// Глобальный менеджер для обработки входящих звонков
class CallManager extends StatefulWidget {
  final Widget child;
  
  const CallManager({super.key, required this.child});

  @override
  State<CallManager> createState() => _CallManagerState();
}

class _CallManagerState extends State<CallManager> {
  final SupabaseService _supabaseService = SupabaseService();
  String? _currentUserId;
  bool _isInCall = false;
  
  @override
  void initState() {
    super.initState();
    _initGlobalCallListener();
  }

  Future<void> _initGlobalCallListener() async {
    _currentUserId = await _supabaseService.getUserId();
    if (_currentUserId == null || !mounted) return;

    _supabaseService.subscribeToUserCalls(
      userId: _currentUserId!,
      onCallReceived: _handleCallInitiation,
      onCallAccepted: _handleCallAccepted,
      onCallEnded: _handleCallEnded,
    );
  }

  void _handleCallInitiation(Map<String, dynamic> payload) {
    if (_isInCall || !mounted) return;
    final String? chatId = payload['chat_id'] as String?;
    final String? fromUserId = payload['from_user_id'] as String?;
    final String? fromNickname = payload['from_nickname'] as String?;

    if (chatId != null && fromUserId != null && fromNickname != null && fromUserId != _currentUserId) {
      _showIncomingCallDialog(
        chatId: chatId,
        fromUserId: fromUserId,
        fromNickname: fromNickname,
      );
    }
  }

  void _handleCallAccepted(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final String chatId = payload['chat_id'];
    final String peerName = await _supabaseService.getNicknameForUser(
          (await _supabaseService.getChats())
              .firstWhere((c) => c['id'] == chatId)['members']
              .firstWhere((m) => m != _currentUserId),
        ) ?? 'Собеседник';

    // Close any open dialogs (like "calling...")
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // Navigate to the call screen for the caller
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => WebRTCCallScreen(
          peerName: peerName,
          chatId: chatId,
          isCaller: true, // This is the caller
        ),
      ),
    );
  }

  void _handleCallEnded(Map<String, dynamic> payload) {
    if (!mounted) return;
    // If there is a dialog or call screen, pop it.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    setState(() => _isInCall = false);
  }

  void _showIncomingCallDialog({
    required String chatId,
    required String fromUserId,
    required String fromNickname,
  }) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.phone_in_talk, color: Colors.green, size: 32),
            const SizedBox(width: 12),
            const Text('Входящий звонок'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              child: Text(
                fromNickname.isNotEmpty ? fromNickname[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 32),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              fromNickname,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Хочет начать звонок',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          // Кнопка отклонить
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              // Отправляем сигнал об отклонении
              _supabaseService.sendCallEnd(chatId: chatId);
            },
            icon: const Icon(Icons.call_end, color: Colors.red),
            label: const Text('Отклонить', style: TextStyle(color: Colors.red)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          
          // Кнопка ответить
          ElevatedButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final navigatorRoot = Navigator.of(context, rootNavigator: true);
              
              navigator.pop();
              setState(() => _isInCall = true);
              
              // Отправляем accept
              await _supabaseService.sendCallAccept(chatId: chatId);
              
              if (!mounted) return;
              
              // Открываем экран звонка
              await navigatorRoot.push(
                MaterialPageRoute(
                  builder: (_) => WebRTCCallScreen(
                    peerName: fromNickname,
                    chatId: chatId,
                    isCaller: false, // Мы принимаем звонок
                  ),
                ),
              );
              
              if (mounted) {
                setState(() => _isInCall = false);
              }
            },
            icon: const Icon(Icons.phone),
            label: const Text('Ответить'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void dispose() {
    _supabaseService.unsubscribeUserCalls();
    super.dispose();
  }
}
