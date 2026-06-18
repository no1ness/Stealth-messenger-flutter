import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/services/signaling/incoming_call_service.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_dialog.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_loading_indicator.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_snack_bar.dart';
import 'package:stealth/themes/apple_liquid/navigation/glass_page_route.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';
import 'package:stealth/ui/screens/webrtc_diagnostics_screen.dart';
import 'package:stealth/webrtc_support.dart';

/// Глобальный слушатель, направляющий входящие звонки в UI.
///
/// Сигналинг идёт через [IncomingCallSignalingService] поверх PocketBase.
/// `LocalAppService` остаётся только для:
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
  final LocalAppService _appService = LocalAppService();
  late final IncomingCallSignalingService _incomingCallService =
      IncomingCallSignalingService(
    knownPeerUuidsProvider: () => _knownContactUuidsCache,
  );

  List<String> _knownContactUuidsCache = const <String>[];

  StreamSubscription<IncomingCallEvent>? _eventsSub;
  String? _currentUserId;
  bool _isInCall = false;
  bool _answeringCall = false;
  String _incomingCallSupportSummary = 'Проверка поддержки звонков...';
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
    Logger.info('[stealth-call] CallManager._initGlobalCallListener started');
    _currentUserId = await _appService.getUserId();
    Logger.info('[stealth-call] CallManager identity resolved',
        extras: {'userId': _currentUserId, 'mounted': mounted});
    if (_currentUserId == null || !mounted) {
      Logger.warn(
          '[stealth-call] CallManager NOT subscribing (userId null or not mounted)');
      return;
    }

    // Warm the contact UUID cache for PbUserIdResolver reverse lookup.
    try {
      final rawContacts = await _appService.getContacts();
      _knownContactUuidsCache = rawContacts
          .map((c) => (c is Map ? c['user_id']?.toString() ?? '' : '') as String)
          .where((id) => id.isNotEmpty)
          .toList();
      Logger.info('[stealth-call] contact cache warmed',
          extras: {'count': _knownContactUuidsCache.length});
    } catch (error) {
      Logger.warn('[stealth-call] contact cache load error',
          extras: {'error': error});
    }

    Logger.info(
        '[stealth-call] CallManager subscribing to PocketBase rtc_signaling');
    try {
      await _incomingCallService.start(selfUserId: _currentUserId!);
      _eventsSub = _incomingCallService.events.listen(_handleIncomingEvent);
      Logger.info('[stealth-call] CallManager subscribed successfully');
    } catch (error) {
      Logger.warn('[stealth-call] CallManager subscribe error',
          extras: {'error': error});
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
    Logger.info('[stealth-call] CallManager._handleIncomingOffer', extras: {
      'roomId': offer.roomId,
      'fromUserId': offer.fromUserId,
      'isInCall': _isInCall,
      'mounted': mounted,
    });
    if (_isInCall || !mounted) {
      Logger.info(
          '[stealth-call] CallManager ignoring call (already in call or not mounted)');
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

    Logger.info('[stealth-call] CallManager recording incoming call');
    await _appService.recordIncomingCall(
      chatId: offer.roomId,
      fromUserId: offer.fromUserId,
      fromNickname: fromNickname,
    );
    if (!mounted) {
      Logger.warn(
          '[stealth-call] CallManager not mounted after recordIncomingCall');
      return;
    }

    Logger.info('[stealth-call] CallManager showing incoming call dialog');
    _showIncomingCallDialog(
      chatId: offer.roomId,
      fromUserId: offer.fromUserId,
      fromNickname: fromNickname,
      isVideoCall: offer.isVideoCall,
      offerSdp: offer.sdp,
    );
  }

  void _handleIncomingHangup(IncomingCallHangup hangup) async {
    Logger.info('[stealth-call] CallManager._handleIncomingHangup', extras: {
      'roomId': hangup.roomId,
      'isInCall': _isInCall,
      'mounted': mounted,
    });
    if (!mounted) return;

    // Если для этого roomId открыт диалог — закрываем.
    final closer = _activeDialogClosers.remove(hangup.roomId);
    if (closer != null) {
      Logger.info('[stealth-call] CallManager closing dialog due to remote hangup');
      closer();
    }

    // Записываем в историю.
    await _appService.markCurrentUserCallEnded(chatId: hangup.roomId);
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

    showStealthDialog<void>(
      context: context,
      title: 'Входящий звонок',
      barrierDismissible: false,
      importance: DialogImportance.high,
      // No top-level actions — the three buttons (Diagnostics / Decline /
      // Answer) live inside `body` so each can drive its own async flow
      // and dismiss the dialog manually. Semantics wrappers preserved
      // verbatim per `call_manager_semantics_test.dart` contract.
      body: Builder(builder: (dialogContext) {
        _activeDialogClosers[chatId] = () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        };
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> refreshSupport() async {
              final support = await getWebRTCSupport();
              if (!dialogContext.mounted) return;
              setDialogState(() {
                _incomingCallSupportSummary = support.summary;
                _incomingCallBlockingIssues = support.blockingIssues;
              });
            }

            if (_incomingCallSupportSummary == 'Проверка поддержки звонков...') {
              refreshSupport();
            }

            final canAnswer =
                _incomingCallBlockingIssues.isEmpty && !_answeringCall;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  child: Text(
                    fromNickname.isNotEmpty
                        ? fromNickname[0].toUpperCase()
                        : '?',
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: AccessibilityIds.callerName,
                  excludeSemantics: true,
                  child: Text(
                    fromNickname,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isVideoCall
                      ? 'Хочет начать защищенный видеозвонок'
                      : 'Хочет начать защищенный аудиозвонок',
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
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).push(
                          GlassPageRoute(
                            builder: (_) => const WebRTCDiagnosticsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.network_check),
                      label: const Text('Диагностика'),
                    ),
                    Semantics(
                      label: AccessibilityIds.decline,
                      button: true,
                      excludeSemantics: true,
                      child: TextButton.icon(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          _activeDialogClosers.remove(chatId);
                          await _appService.markIncomingCallDeclined(
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
                          'Отклонить',
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
                                Logger.info('[stealth-call] Answer pressed',
                                    extras: {'chatId': chatId});
                                final navigatorRoot = Navigator.of(
                                  context,
                                  rootNavigator: true,
                                );
                                final dialogNavigator =
                                    Navigator.of(dialogContext);

                                setDialogState(() => _answeringCall = true);
                                final preflightError =
                                    await requestWebRTCAudioPreflight(
                                  requireVideo: isVideoCall,
                                );
                                Logger.info('[stealth-call] preflight result',
                                    extras: {'error': preflightError ?? 'OK'});
                                if (preflightError != null) {
                                  if (dialogContext.mounted) {
                                    showStealthSnackBar(
                                      dialogContext,
                                      preflightError,
                                      kind: SnackKind.danger,
                                    );
                                    setDialogState(
                                        () => _answeringCall = false);
                                  }
                                  return;
                                }

                                dialogNavigator.pop();
                                _activeDialogClosers.remove(chatId);
                                setState(() => _isInCall = true);

                                if (!mounted) {
                                  Logger.warn(
                                      '[stealth-call] not mounted after dialog pop');
                                  return;
                                }

                                Logger.info(
                                    '[stealth-call] pushing WebRTCCallScreen with initialOffer');
                                await navigatorRoot.push(
                                  GlassPageRoute.modal(
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
                                Logger.info('[stealth-call] call screen popped');

                                if (mounted) {
                                  setState(() => _isInCall = false);
                                  _answeringCall = false;
                                }
                              },
                        icon: _answeringCall
                            ? const StealthLoadingIndicator(
                                size: 18,
                                strokeWidth: 2,
                              )
                            : const Icon(Icons.phone),
                        label: Text(canAnswer ? 'Ответить' : 'Недоступно'),
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
                ),
              ],
            );
          },
        );
      }),
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
