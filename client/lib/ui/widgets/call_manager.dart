import 'package:flutter/material.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';
import 'package:stealth/webrtc_support.dart';

/// Глобальный слушатель, направляющий входящие звонки в UI.
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
  bool _answeringCall = false;
  String _incomingCallSupportSummary = 'Checking call support...';
  List<String> _incomingCallBlockingIssues = const <String>[];

  @override
  void initState() {
    super.initState();
    _initGlobalCallListener();
  }

  Future<void> _initGlobalCallListener() async {
    // ignore: avoid_print
    print('[stealth-call] CallManager._initGlobalCallListener started');
    _currentUserId = await _supabaseService.getUserId();
    // ignore: avoid_print
    print('[stealth-call] CallManager userId=$_currentUserId mounted=$mounted');
    if (_currentUserId == null || !mounted) {
      // ignore: avoid_print
      print('[stealth-call] CallManager NOT subscribing (userId null or not mounted)');
      return;
    }

    // ignore: avoid_print
    print('[stealth-call] CallManager subscribing to user_calls:$_currentUserId');
    _supabaseService.subscribeToUserCalls(
      userId: _currentUserId!,
      onCallReceived: _handleCallInitiation,
      onCallAccepted: _handleCallAccepted,
      onCallEnded: _handleCallEnded,
    );
    // ignore: avoid_print
    print('[stealth-call] CallManager subscribed successfully');
  }

  void _handleCallInitiation(Map<String, dynamic> payload) async {
    // ignore: avoid_print
    print('[stealth-call] CallManager._handleCallInitiation payload=$payload isInCall=$_isInCall mounted=$mounted');
    if (_isInCall || !mounted) {
      // ignore: avoid_print
      print('[stealth-call] CallManager ignoring call (already in call or not mounted)');
      return;
    }

    final chatId = payload['chat_id'] as String?;
    final fromUserId = payload['from_user_id'] as String?;
    final fromNickname = payload['from_nickname'] as String?;
    final isVideoCall = payload['call_type'] == 'video';
    // ignore: avoid_print
    print('[stealth-call] CallManager parsed: chatId=$chatId fromUserId=$fromUserId fromNickname=$fromNickname isVideo=$isVideoCall');
    if (chatId == null ||
        fromUserId == null ||
        fromNickname == null ||
        fromUserId == _currentUserId) {
      // ignore: avoid_print
      print('[stealth-call] CallManager invalid payload or self-call, ignoring');
      return;
    }

    // ignore: avoid_print
    print('[stealth-call] CallManager recording incoming call');
    await _supabaseService.recordIncomingCall(
      chatId: chatId,
      fromUserId: fromUserId,
      fromNickname: fromNickname,
    );
    if (!mounted) {
      // ignore: avoid_print
      print('[stealth-call] CallManager not mounted after recordIncomingCall');
      return;
    }

    // ignore: avoid_print
    print('[stealth-call] CallManager showing incoming call dialog');
    _showIncomingCallDialog(
      chatId: chatId,
      fromUserId: fromUserId,
      fromNickname: fromNickname,
      isVideoCall: isVideoCall,
    );
  }

  void _handleCallAccepted(Map<String, dynamic> payload) async {
    // ВАЖНО: здесь НИЧЕГО не нужно делать с навигацией. Экран звонка у
    // вызывающей стороны уже открыт из `contacts_screen.dart` с
    // `isCaller: true`. Ранее эта функция делала `navigator.pop()`, а затем
    // `push`, из-за чего срабатывал `PopScope` в `WebRTCCallScreen`,
    // вызывался `_hangUp` и отправлялся `call_end`, который закрывал звонок
    // у принимающей стороны (эмулятора) до того, как успевал установиться
    // WebRTC-коннект.
    //
    // Событие `call_accept` пробрасывается в `SupabaseService.callAcceptedStream`,
    // и уже активный `WebRTCCallScreen` сам отправит offer.
  }

  void _handleCallEnded(Map<String, dynamic> payload) async {
    // ignore: avoid_print
    print(
      '[stealth-call] CallManager._handleCallEnded payload=$payload '
      'isInCall=$_isInCall mounted=$mounted',
    );
    if (!mounted) {
      return;
    }

    final chatId = payload['chat_id'] as String?;
    if (chatId != null) {
      await _supabaseService.markCurrentUserCallEnded(chatId: chatId);
      if (!mounted) {
        return;
      }
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      // ignore: avoid_print
      print('[stealth-call] CallManager popping top route due to call_end');
      navigator.pop();
    }
    setState(() => _isInCall = false);
  }

  void _showIncomingCallDialog({
    required String chatId,
    required String fromUserId,
    required String fromNickname,
    required bool isVideoCall,
  }) {
    if (!mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> refreshSupport() async {
            final support = await getWebRTCSupport();
            if (!dialogContext.mounted) {
              return;
            }
            setDialogState(() {
              _incomingCallSupportSummary = support.summary;
              _incomingCallBlockingIssues = support.blockingIssues;
            });
          }

          if (_incomingCallSupportSummary == 'Checking call support...') {
            refreshSupport();
          }

          final canAnswer = _incomingCallBlockingIssues.isEmpty && !_answeringCall;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.phone_in_talk, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text('Incoming call'),
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
                Semantics(
                  label: AccessibilityIds.callerName,
                  excludeSemantics: true,
                  child: Text(
                    fromNickname,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isVideoCall
                      ? 'Wants to start a secure video call'
                      : 'Wants to start a secure audio call',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                Text(
                  _incomingCallSupportSummary,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                if (_incomingCallBlockingIssues.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _incomingCallBlockingIssues.join('\n'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).push(
                    MaterialPageRoute(
                      builder: (_) => const WebRTCDiagnosticsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.network_check),
                label: const Text('Diagnostics'),
              ),
              Semantics(
                label: AccessibilityIds.decline,
                button: true,
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _supabaseService.markIncomingCallDeclined(
                      chatId: chatId,
                      fromUserId: fromUserId,
                    );
                    await _supabaseService.sendCallEnd(chatId: chatId);
                  },
                  icon: const Icon(Icons.call_end, color: Colors.red),
                  label: const Text(
                    'Decline',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              Semantics(
                label: AccessibilityIds.answer,
                button: true,
                excludeSemantics: true,
                child: ElevatedButton.icon(
                  onPressed: !canAnswer
                    ? null
                    : () async {
                        // ignore: avoid_print
                        print('[stealth-call] Answer pressed for chat=$chatId');
                        final navigatorRoot = Navigator.of(
                          context,
                          rootNavigator: true,
                        );
                        final dialogNavigator = Navigator.of(dialogContext);
                        final messenger = ScaffoldMessenger.of(dialogContext);

                        setDialogState(() => _answeringCall = true);
                        final preflightError = await requestWebRTCAudioPreflight(
                          requireVideo: isVideoCall,
                        );
                        // ignore: avoid_print
                        print(
                          '[stealth-call] preflight result: ${preflightError ?? 'OK'}',
                        );
                        if (preflightError != null) {
                          if (dialogContext.mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(preflightError)),
                            );
                            setDialogState(() => _answeringCall = false);
                          }
                          return;
                        }

                        dialogNavigator.pop();
                        setState(() => _isInCall = true);

                        if (!mounted) {
                          // ignore: avoid_print
                          print('[stealth-call] not mounted after dialog pop');
                          return;
                        }

                        // ВАЖНО: `call_accept` отправляет сам экран звонка у
                        // принимающей стороны ПОСЛЕ того, как подписался на
                        // chat_calls. Иначе вызывающая сторона получает
                        // call_accept и шлёт offer в канал раньше, чем callee
                        // успевает подписаться, и сигналинг теряется.
                        // ignore: avoid_print
                        print('[stealth-call] pushing WebRTCCallScreen');
                        await navigatorRoot.push(
                          MaterialPageRoute(
                            builder: (_) => WebRTCCallScreen(
                              peerName: fromNickname,
                              chatId: chatId,
                              isCaller: false,
                              isVideoCall: isVideoCall,
                            ),
                          ),
                        );
                        // ignore: avoid_print
                        print('[stealth-call] call screen popped');

                        if (mounted) {
                          setState(() => _isInCall = false);
                          _answeringCall = false;
                        }
                      },
                icon: _answeringCall
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.phone),
                label: Text(canAnswer ? 'Answer' : 'Unavailable'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            ],
          );
        },
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
