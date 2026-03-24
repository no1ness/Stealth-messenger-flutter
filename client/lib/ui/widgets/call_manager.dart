import 'package:flutter/material.dart';
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
    _currentUserId = await _supabaseService.getUserId();
    if (_currentUserId == null || !mounted) {
      return;
    }

    _supabaseService.subscribeToUserCalls(
      userId: _currentUserId!,
      onCallReceived: _handleCallInitiation,
      onCallAccepted: _handleCallAccepted,
      onCallEnded: _handleCallEnded,
    );
  }

  void _handleCallInitiation(Map<String, dynamic> payload) async {
    if (_isInCall || !mounted) {
      return;
    }

    final chatId = payload['chat_id'] as String?;
    final fromUserId = payload['from_user_id'] as String?;
    final fromNickname = payload['from_nickname'] as String?;
    if (chatId == null ||
        fromUserId == null ||
        fromNickname == null ||
        fromUserId == _currentUserId) {
      return;
    }

    await _supabaseService.recordIncomingCall(
      chatId: chatId,
      fromUserId: fromUserId,
      fromNickname: fromNickname,
    );
    if (!mounted) {
      return;
    }

    _showIncomingCallDialog(
      chatId: chatId,
      fromUserId: fromUserId,
      fromNickname: fromNickname,
    );
  }

  void _handleCallAccepted(Map<String, dynamic> payload) async {
    if (!mounted) {
      return;
    }

    final chatId = payload['chat_id'] as String;
    final chats = await _supabaseService.getChats();
    final chat = chats.firstWhere((item) => item['id'] == chatId);
    final peerId = (chat['members'] as List<dynamic>)
        .cast<String>()
        .firstWhere((member) => member != _currentUserId);
    final peerName =
        await _supabaseService.getNicknameForUser(peerId) ?? 'Peer';

    if (!mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    final navigatorRoot = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }

    navigatorRoot.push(
      MaterialPageRoute(
        builder: (_) => WebRTCCallScreen(
          peerName: peerName,
          chatId: chatId,
          isCaller: true,
        ),
      ),
    );
  }

  void _handleCallEnded(Map<String, dynamic> payload) async {
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
      navigator.pop();
    }
    setState(() => _isInCall = false);
  }

  void _showIncomingCallDialog({
    required String chatId,
    required String fromUserId,
    required String fromNickname,
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
                Text(
                  fromNickname,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wants to start a secure audio call',
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
              TextButton.icon(
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
              ElevatedButton.icon(
                onPressed: !canAnswer
                    ? null
                    : () async {
                        final navigatorRoot = Navigator.of(
                          context,
                          rootNavigator: true,
                        );
                        final dialogNavigator = Navigator.of(dialogContext);
                        final messenger = ScaffoldMessenger.of(dialogContext);

                        setDialogState(() => _answeringCall = true);
                        final preflightError = await requestWebRTCAudioPreflight();
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
                        await _supabaseService.sendCallAccept(chatId: chatId);

                        if (!mounted) {
                          return;
                        }

                        await navigatorRoot.push(
                          MaterialPageRoute(
                            builder: (_) => WebRTCCallScreen(
                              peerName: fromNickname,
                              chatId: chatId,
                              isCaller: false,
                            ),
                          ),
                        );

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
