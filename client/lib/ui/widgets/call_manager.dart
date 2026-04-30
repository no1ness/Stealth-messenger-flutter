import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/services/signaling/incoming_call_service.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';
import 'package:stealth/webrtc_support.dart';

/// Глобальный слушатель, направляющий входящие звонки в UI.
///
/// Сигналинг идёт через [IncomingCallSignalingService] поверх PocketBase.
/// `SupabaseService` остаётся только для:
/// - получения текущего `selfUserId` (UUID, сгенерированный при
///   регистрации, хранится локально),
/// - истории входящих звонков (`recordIncomingCall`,
///   `markIncomingCallDeclined`).
class CallManager extends StatefulWidget {
  final Widget child;

  const CallManager({super.key, required this.child});

  @override
  State<CallManager> createState() => _CallManagerState();
}

class _CallManagerState extends State<CallManager> {
  final SupabaseService _supabaseService = SupabaseService();
  final IncomingCallSignalingService _incomingCallService =
      IncomingCallSignalingService();

  StreamSubscription<IncomingCallEvent>? _eventsSub;
  String? _currentUserId;
  bool _isInCall = false;
  bool _answeringCall = false;
  String _incomingCallSupportSummary = 'Checking call support...';
  List<String> _incomingCallBlockingIssues = const <String>[];

  /// roomId → закрытие текущего диалога входящего звонка. Используется,
  /// чтобы remote hangup мог автоматически дёрнуть `Navigator.pop` для
  /// активного диалога.
  final Map<String, VoidCallback> _activeDialogClosers = {};

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
    print('[stealth-call] CallManager subscribing to PocketBase rtc_signaling');
    try {
      await _incomingCallService.start(selfUserId: _currentUserId!);
      _eventsSub = _incomingCallService.events.listen(_handleIncomingEvent);
      // ignore: avoid_print
      print('[stealth-call] CallManager subscribed successfully');
    } catch (error) {
      // ignore: avoid_print
      print('[stealth-call] CallManager subscribe error: $error');
    }
  }

  void _handleIncomingEvent(IncomingCallEvent event) {
    switch (event) {
      case IncomingCallOffer():
        _handleIncomingOffer(event);
      case IncomingCallHangup():
        _handleIncomingHangup(event);
    }
  }

  void _handleIncomingOffer(IncomingCallOffer offer) async {
    // ignore: avoid_print
    print(
      '[stealth-call] CallManager._handleIncomingOffer roomId=${offer.roomId} '
      'from=${offer.fromUserId} isInCall=$_isInCall mounted=$mounted',
    );
    if (_isInCall || !mounted) {
      // ignore: avoid_print
      print('[stealth-call] CallManager ignoring call (already in call or not mounted)');
      return;
    }
    if (offer.fromUserId == _currentUserId) {
      // self-call (теоретически не должно случаться, фильтр PocketBase
      // фильтрует по target, но защищаемся на всякий случай).
      return;
    }

    final fromNickname = offer.fromNickname.isEmpty
        ? 'Unknown'
        : offer.fromNickname;

    // ignore: avoid_print
    print('[stealth-call] CallManager recording incoming call');
    await _supabaseService.recordIncomingCall(
      chatId: offer.roomId,
      fromUserId: offer.fromUserId,
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
      chatId: offer.roomId,
      fromUserId: offer.fromUserId,
      fromNickname: fromNickname,
      isVideoCall: offer.isVideoCall,
      offerSdp: offer.sdp,
    );
  }

  void _handleIncomingHangup(IncomingCallHangup hangup) async {
    // ignore: avoid_print
    print(
      '[stealth-call] CallManager._handleIncomingHangup roomId=${hangup.roomId} '
      'isInCall=$_isInCall mounted=$mounted',
    );
    if (!mounted) return;

    // Если для этого roomId открыт диалог — закрываем.
    final closer = _activeDialogClosers.remove(hangup.roomId);
    if (closer != null) {
      // ignore: avoid_print
      print('[stealth-call] CallManager closing dialog due to remote hangup');
      closer();
    }

    // Записываем в историю.
    await _supabaseService.markCurrentUserCallEnded(chatId: hangup.roomId);
    if (!mounted) return;

    // Если активен сам экран звонка — он сам обработает hangup через
    // свой WebRtcSignalingService.incoming → _handleRemoteHangup.
    // Здесь дополнительно ничего не делаем.
  }

  void _showIncomingCallDialog({
    required String chatId,
    required String fromUserId,
    required String fromNickname,
    required bool isVideoCall,
    required Map<String, dynamic> offerSdp,
  }) {
    if (!mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Регистрируем closer чтобы remote hangup мог закрыть диалог.
        _activeDialogClosers[chatId] = () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        };
        return StatefulBuilder(
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

            final canAnswer =
                _incomingCallBlockingIssues.isEmpty && !_answeringCall;

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
                      _activeDialogClosers.remove(chatId);
                      await _supabaseService.markIncomingCallDeclined(
                        chatId: chatId,
                        fromUserId: fromUserId,
                      );
                      final selfId = _currentUserId;
                      if (selfId != null) {
                        await _incomingCallService.declineCall(
                          roomId: chatId,
                          callerUserId: fromUserId,
                          selfUserId: selfId,
                        );
                      }
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
                            final preflightError =
                                await requestWebRTCAudioPreflight(
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
                            _activeDialogClosers.remove(chatId);
                            setState(() => _isInCall = true);

                            if (!mounted) {
                              // ignore: avoid_print
                              print('[stealth-call] not mounted after dialog pop');
                              return;
                            }

                            // ignore: avoid_print
                            print('[stealth-call] pushing WebRTCCallScreen with initialOffer');
                            await navigatorRoot.push(
                              MaterialPageRoute(
                                builder: (_) => WebRTCCallScreen(
                                  peerName: fromNickname,
                                  chatId: chatId,
                                  isCaller: false,
                                  isVideoCall: isVideoCall,
                                  initialOffer: offerSdp,
                                  callerUserId: fromUserId,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void dispose() {
    // ignore: discarded_futures
    _eventsSub?.cancel();
    // ignore: discarded_futures
    _incomingCallService.stop();
    super.dispose();
  }
}
