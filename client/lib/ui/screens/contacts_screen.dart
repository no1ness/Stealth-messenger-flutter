import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_dialog.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_loading_indicator.dart';
import 'package:stealth/themes/apple_liquid/feedback/stealth_snack_bar.dart';
import 'package:stealth/themes/apple_liquid/navigation/glass_page_route.dart';
import 'package:stealth/themes/apple_liquid/widgets/contacts/contact_tile.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';
import 'package:stealth/ui/sheets/user_detail_sheet.dart';
import 'package:stealth/ui/widgets/empty_state.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/services/user_directory/presence_service.dart';
import 'package:stealth/services/user_directory/user_directory_service.dart';
import 'package:stealth/ui/screens/chats_screen.dart';
import 'package:stealth/ui/screens/contacts_data_source.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';
import 'package:stealth/webrtc_support.dart';

class ContactsScreen extends StatefulWidget {
  ContactsScreen({super.key, ContactsDataSource? dataSource})
      : _dataSource = dataSource ??
            LocalContactsDataSource(LocalAppService());

  final ContactsDataSource _dataSource;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addContactController = TextEditingController();
  ContactsDataSource get _appService => widget._dataSource;
  bool _loading = true;
  bool _startingCall = false;
  List<Map<String, dynamic>> _contacts = const [];
  StreamSubscription<Map<String, dynamic>>? _presenceSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _subscribeToPresence();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addContactController.dispose();
    _presenceSub?.cancel();
    super.dispose();
  }

  void _subscribeToPresence() {
    _presenceSub?.cancel();
    _presenceSub = PresenceService().onPresenceChange.listen((profile) {
      final userId = profile['userId'] as String?;
      if (userId == null) return;
      setState(() {
        final idx = _contacts.indexWhere(
          (c) => (c['user_id'] ?? c['contact_user_id']) == userId,
        );
        if (idx >= 0) {
          _contacts[idx]['isOnline'] = profile['isOnline'];
          _contacts[idx]['lastSeen'] = profile['lastSeen'];
        }
      });
    });
  }

  Future<void> _loadContacts() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    final rows = await _appService.getContacts();
    final cached = UserDirectoryService().getCachedProfiles();

    final merged = <String, Map<String, dynamic>>{};
    for (final contact in rows.cast<Map<String, dynamic>>()) {
      final userId = (contact['user_id'] ?? contact['contact_user_id'])?.toString() ?? '';
      if (userId.isNotEmpty) {
        final profile = cached.where((p) => p['userId'] == userId).firstOrNull;
        if (profile != null) {
          contact['isOnline'] = profile['isOnline'] ?? contact['isOnline'];
          contact['lastSeen'] = profile['lastSeen'] ?? contact['lastSeen'];
          if (profile['deviceModel'] != null) contact['deviceModel'] = profile['deviceModel'];
          if (profile['platform'] != null) contact['platform'] = profile['platform'];
          if (profile['appVersion'] != null) contact['appVersion'] = profile['appVersion'];
        }
        merged[userId] = contact;
      }
    }

    for (final profile in cached) {
      final uid = profile['userId']?.toString() ?? '';
      if (uid.isEmpty || merged.containsKey(uid)) continue;
      final autoContact = <String, dynamic>{
        'user_id': uid,
        'contact_user_id': uid,
        'name': uid,
        'nickname': uid,
        'isOnline': profile['isOnline'] ?? false,
        'lastSeen': profile['lastSeen'] ?? '',
        'deviceModel': profile['deviceModel'] ?? '',
        'platform': profile['platform'] ?? '',
        'appVersion': profile['appVersion'] ?? '',
        'auto_populated': true,
      };
      merged[uid] = autoContact;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _contacts = merged.values.toList();
      _loading = false;
    });
  }

  Future<void> _showContactActions(Map<String, dynamic> contact) async {
    if (!mounted) {
      return;
    }

    final name = contact['name'] as String? ?? 'Неизвестный';
    final autoPopulated = contact['auto_populated'] == true;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Информация'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await showUserDetailSheet(context, contact);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Открыть чат'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _openChat(contact);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Проверить код безопасности'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _verifySafetyNumber(contact);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.call),
                  title: const Text('Начать звонок'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _startCall(contact, isVideoCall: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Начать видеозвонок'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _startCall(contact, isVideoCall: true);
                  },
                ),
                ListTile(
                  leading: autoPopulated
                      ? const Icon(Icons.visibility_off_outlined)
                      : const Icon(Icons.delete_outline),
                  title: Text(autoPopulated ? 'Скрыть' : 'Удалить $name'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final snackMsg = autoPopulated ? '$name скрыт' : '$name удален';
                    Navigator.of(context).pop();
                    final userId = (contact['user_id'] ?? contact['contact_user_id'])?.toString();
                    if (userId != null && userId.isNotEmpty) {
                      await _appService.deleteContact(userId);
                      await _loadContacts();
                    }
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(snackMsg),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _verifySafetyNumber(Map<String, dynamic> contact) async {
    final userId = contact['user_id'] as String?;
    final name = contact['name'] as String? ?? 'Контакт';
    if (userId == null) return;

    if (mounted) {
      showStealthDialog<void>(
        context: context,
        title: 'Генерация отпечатка',
        barrierDismissible: false,
        body: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StealthLoadingIndicator(size: 20, strokeWidth: 2),
            SizedBox(width: AppSpacing.md),
            Text('Генерация отпечатка...'),
          ],
        ),
      );
    }

    final safetyNumber = await _appService.getSafetyNumber(userId);

    if (mounted) {
      Navigator.of(context).pop(); // Закрываем диалог загрузки

      showStealthDialog<void>(
        context: context,
        title: 'Код безопасности — $name',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Сравните этот номер с контактом. Если он точно совпадает, ваше сквозное шифрование безопасно.',
              style: AppTypography.caption1
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              safetyNumber ?? 'Ошибка генерации номера',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                fontFamily: 'GeistMono',
                color: AppColors.systemBlue,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: const [
          StealthDialogAction<void>.primary(label: 'OK', result: null),
        ],
      );
    }
  }

  Future<void> _showAddContactSheet() async {
    final results = <Map<String, dynamic>>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> search() async {
              final rows = await _appService.searchUsers(
                _addContactController.text,
              );
              setModalState(() {
                results
                  ..clear()
                  ..addAll(rows.cast<Map<String, dynamic>>());
              });
            }

            Future<void> pasteAndSearch() async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final pastedText = data?.text?.trim() ?? '';
              if (pastedText.isEmpty) {
                if (!context.mounted) {
                  return;
                }
                showStealthSnackBar(
                  context,
                  'Буфер обмена пуст',
                  kind: SnackKind.warn,
                );
                return;
              }

              _addContactController.text = pastedText;
              await search();
            }

            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                top: AppSpacing.md,
                bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: AccessibilityIds.contactBundleInput,
                    textField: true,
                    child: TextField(
                      controller: _addContactController,
                      decoration: const InputDecoration(
                        hintText: 'Вставьте данные контакта',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => search(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Подсказка: откройте Профиль на другом устройстве и скопируйте данные контакта для E2E-сообщений.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: pasteAndSearch,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Вставить контакт'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 280,
                    child: results.isEmpty
                        ? const Center(child: Text('Пользователи не найдены'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final result = results[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    _initials(result['name'] as String?),
                                  ),
                                ),
                                title: Text(result['name'] as String? ?? 'Неизвестный'),
                                subtitle: Text(
                                  result['user_id'] as String? ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Semantics(
                                  label: AccessibilityIds.saveContact,
                                  button: true,
                                  child: FilledButton(
                                    onPressed: () async {
                                      await _appService.addContact(
                                        result['user_id'] as String,
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      Navigator.of(context).pop();
                                      await _loadContacts();
                                    },
                                    child: const Text('Добавить'),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openChat(Map<String, dynamic> contact) async {
    final userId = contact['user_id'] as String?;
    if (userId == null || userId.isEmpty) {
      return;
    }

    final chatId = await _appService.findOrCreatePrivateChatWith(userId);
    if (!mounted || chatId == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatsScreen(initialChatId: chatId)),
    );
  }

  Future<void> _startCall(
    Map<String, dynamic> contact, {
    required bool isVideoCall,
  }) async {
    if (_startingCall) {
      return;
    }

    setState(() => _startingCall = true);
    final support = await getWebRTCSupport();
    if (!support.isSupported) {
      if (mounted) {
        showStealthSnackBar(
          context,
          support.blockingIssues.join(' '),
          kind: SnackKind.danger,
        );
      }
      if (mounted) {
        setState(() => _startingCall = false);
      }
      return;
    }

    final preflightError = await requestWebRTCAudioPreflight(
      requireVideo: isVideoCall,
    );
    if (preflightError != null) {
      if (mounted) {
        showStealthSnackBar(
          context,
          preflightError,
          kind: SnackKind.danger,
        );
        setState(() => _startingCall = false);
      }
      return;
    }

    final userId = contact['user_id'] as String?;
    if (userId == null || userId.isEmpty) {
      if (mounted) {
        setState(() => _startingCall = false);
      }
      return;
    }

    final chatId = await _appService.findOrCreatePrivateChatWith(userId);
    if (!mounted || chatId == null) {
      if (mounted) {
        setState(() => _startingCall = false);
      }
      return;
    }

    // В PocketBase-архитектуре sendCallInitiation удалён: сам offer,
    // который шлёт WebRTCCallScreen после открытия, и есть «звонок».
    // Это устраняет лишний канал связи и упрощает race-conditions.
    await Navigator.of(context).push(
      GlassPageRoute.modal(
        builder: (_) => WebRTCCallScreen(
          peerName: (contact['name'] as String?) ?? 'Контакт',
          chatId: chatId,
          isCaller: true,
          isVideoCall: isVideoCall,
        ),
      ),
    );
    if (mounted) {
      setState(() => _startingCall = false);
    }
  }

  String _initials(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '?';
    }

    final parts = value.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _contacts
        : _contacts
            .where(
              (contact) => (contact['name'] as String? ?? '')
                  .toLowerCase()
                  .contains(query),
            )
            .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: GlassAppBar(title: 'Контакты'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: EdgeInsets.all(
              constraints.maxWidth >= 900 ? AppSpacing.xl : AppSpacing.md,
            ),
            child: Column(
              children: [
                GlassTextField(
                  controller: _searchController,
                  hintText: 'Поиск контактов',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textSecondary,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    label: AccessibilityIds.addContact,
                    button: true,
                    child: FilledButton.icon(
                      onPressed: _showAddContactSheet,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Добавить контакт'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadContacts,
                    child: _loading
                        ? const Center(child: StealthLoadingIndicator())
                        : filtered.isEmpty
                            ? Semantics(
                                label: 'Нет контактов',
                                child: const StealthEmptyState.contacts(),
                              )
                            : GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: constraints.maxWidth >= 1200
                                      ? 3
                                      : (constraints.maxWidth >= 700 ? 2 : 1),
                                  crossAxisSpacing: AppSpacing.md,
                                  mainAxisSpacing: AppSpacing.md,
                                  childAspectRatio: constraints.maxWidth >= 700
                                      ? 2.3
                                      : 2.8,
                                ),
                                itemCount: filtered.length,
                                padding: EdgeInsets.only(
                                  bottom: MediaQuery.of(context).padding.bottom +
                                      AppSpacing.bottomBarOverlap,
                                ),
                                itemBuilder: (context, index) {
                                  final contact = filtered[index];
                                  final isOnline = contact['isOnline'] as bool?;
                                  final autoPopulated = contact['auto_populated'] == true;
                                  return Opacity(
                                    opacity: autoPopulated ? 0.85 : 1.0,
                                    child: ContactTile(
                                      contact: contact,
                                      isOnline: isOnline,
                                      onTap: _startingCall
                                          ? () {}
                                          : () => _openChat(contact),
                                      onLongPress: () =>
                                          _showContactActions(contact),
                                      trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Открыть чат',
                                          onPressed: _startingCall
                                              ? null
                                              : () => _openChat(contact),
                                          icon: const Icon(
                                            Icons.chat_bubble_outline,
                                            color: AppColors.systemBlue,
                                          ),
                                        ),
                                        Semantics(
                                          label: AccessibilityIds.startCall,
                                          button: true,
                                          excludeSemantics: true,
                                          child: IconButton(
                                            tooltip: 'Начать звонок',
                                            onPressed: _startingCall
                                                ? null
                                                : () => _startCall(
                                                      contact,
                                                      isVideoCall: false,
                                                    ),
                                            icon: _startingCall
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        StealthLoadingIndicator(
                                                      size: 18,
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.call_outlined,
                                                    color: AppColors
                                                        .statusSuccess,
                                                  ),
                                          ),
                                        ),
                                        Semantics(
                                          label:
                                              AccessibilityIds.startVideoCall,
                                          button: true,
                                          excludeSemantics: true,
                                          child: IconButton(
                                            tooltip: 'Начать видеозвонок',
                                            onPressed: _startingCall
                                                ? null
                                                : () => _startCall(
                                                      contact,
                                                      isVideoCall: true,
                                                    ),
                                            icon: const Icon(
                                              Icons.videocam_outlined,
                                              color: AppColors.systemBlue,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Дополнительные опции',
                                          onPressed: () =>
                                              _showContactActions(contact),
                                          icon: const Icon(
                                            Icons.more_horiz,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                },
                              ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
