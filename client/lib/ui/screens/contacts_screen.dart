import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stealth/di.dart';
import 'package:stealth/local_app_service.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/ui/screens/chats/safety_number_dialog.dart';
import 'package:stealth/ui/screens/chats_screen.dart';
import 'package:stealth/ui/screens/contacts_data_source.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';
import 'package:stealth/webrtc_support.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key, this.dataSource});

  /// Optional override for tests. When `null` the screen resolves a
  /// `LocalContactsDataSource` from the Riverpod `localAppServiceProvider`
  /// at first read inside the state.
  final ContactsDataSource? dataSource;

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addContactController = TextEditingController();
  late final ContactsDataSource _appService = widget.dataSource ??
      LocalContactsDataSource(ref.read(localAppServiceProvider));
  bool _loading = true;
  bool _startingCall = false;
  List<Map<String, dynamic>> _contacts = const [];

  /// Cache of per-contact safety-number verification status, keyed by
  /// `user_id`. Populated alongside [_loadContacts] so the grid item
  /// builder can render the ✓ / ⚠ indicator synchronously.
  Map<String, ContactVerificationStatus> _verificationByUserId = const {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addContactController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    final rows = await _appService.getContacts();
    final verification = await _loadVerificationStatuses(
      rows.cast<Map<String, dynamic>>(),
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _contacts = rows.cast<Map<String, dynamic>>();
      _verificationByUserId = verification;
      _loading = false;
    });
  }

  /// Computes the safety-number verification state for every contact
  /// in [contacts]. Reads through the Riverpod-provided
  /// [LocalAppService] rather than the [ContactsDataSource]
  /// abstraction so the (test-only) `dataSource` constructor override
  /// in widget tests does not need to mock these calls — when a fake
  /// data source is in use we just return an empty map.
  ///
  /// Backed by [LocalAppService.batchVerificationStatuses] so the own
  /// public key is read from secure storage exactly once per render
  /// instead of O(N) per-contact lookups.
  Future<Map<String, ContactVerificationStatus>> _loadVerificationStatuses(
    List<Map<String, dynamic>> contacts,
  ) async {
    // Widget tests pass a synthetic ContactsDataSource through the
    // constructor; routing verification through LocalAppService in
    // that case would require the tests to mount real storage. Skip
    // the lookup when the override is active.
    if (widget.dataSource != null) {
      return const {};
    }
    try {
      final appService = ref.read(localAppServiceProvider);
      return appService.batchVerificationStatuses(contacts);
    } catch (_) {
      // Best-effort load — a failed batch lookup must not blank the
      // entire contacts list.
      return const {};
    }
  }

  Future<void> _deleteContact(Map<String, dynamic> contact) async {
    final userId = contact['user_id'] as String?;
    final name = contact['name'] as String? ?? 'Contact';
    if (userId == null || userId.isEmpty) {
      return;
    }

    await _appService.deleteContact(userId);
    await _loadContacts();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name removed')),
    );
  }

  Future<void> _showContactActions(Map<String, dynamic> contact) async {
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final name = contact['name'] as String? ?? 'Unknown';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Open chat'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _openChat(contact);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Verify Safety Number'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _verifySafetyNumber(contact);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.call),
                  title: const Text('Start call'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _startCall(contact, isVideoCall: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Start video call'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _startCall(contact, isVideoCall: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text('Remove $name'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _deleteContact(contact);
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
    final name = contact['name'] as String? ?? 'Contact';
    if (userId == null || userId.isEmpty || !mounted) {
      return;
    }

    final confirmed = await SafetyNumberDialog.show(
      context,
      contactUserId: userId,
      contactName: name,
    );

    // Reload contacts whenever the dialog actually persisted a
    // verification — the ✓ indicator should appear without requiring
    // the user to swipe-to-refresh.
    if (confirmed == true) {
      await _loadContacts();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name marked as verified')),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Clipboard is empty')),
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
                        hintText: 'Paste contact bundle',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => search(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Tip: open Profile on the other device and copy its contact bundle for E2E messaging.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: pasteAndSearch,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Paste contact'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 280,
                    child: results.isEmpty
                        ? const Center(child: Text('No users found'))
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
                                title: Text(result['name'] as String? ?? 'Unknown'),
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
                                    child: const Text('Add'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(support.blockingIssues.join(' '))),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(preflightError)),
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
      MaterialPageRoute(
        builder: (_) => WebRTCCallScreen(
          peerName: (contact['name'] as String?) ?? 'Contact',
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
        child: GlassAppBar(title: 'Contacts'),
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
                  hintText: 'Search contacts',
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
                      label: const Text('Add contact'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadContacts,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : filtered.isEmpty
                            ? ListView(
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height * 0.4,
                                  ),
                                  Center(
                                    child: Semantics(
                                      label: 'No contacts',
                                      child: Text(
                                        'No contacts found',
                                        style: AppTypography.body.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
                                padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 80),
                                itemBuilder: (context, index) {
                                  final contact = filtered[index];
                                  final name = (contact['name'] as String?) ?? 'Unknown';
                                  final verification = _verificationByUserId[
                                      (contact['user_id'] as String?) ?? ''];
                                  return Semantics(
                                    label: AccessibilityIds.contact(name),
                                    button: true,
                                    child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onLongPress: () => _showContactActions(contact),
                                    child: GlassContainer(
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 24,
                                            backgroundColor:
                                                AppColors.systemBlue,
                                            child: Text(
                                              _initials(
                                                contact['name'] as String?,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.md),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        (contact['name'] as String?) ??
                                                            'Unknown',
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: AppTypography
                                                            .body
                                                            .copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    if (verification != null)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                          left: AppSpacing.xs,
                                                        ),
                                                        child: _VerificationBadge(
                                                          status: verification,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(
                                                  height: AppSpacing.xs,
                                                ),
                                                Text(
                                                  (contact['user_id']
                                                          as String?) ??
                                                      '',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AppTypography.caption1
                                                      .copyWith(
                                                    color:
                                                        AppColors.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Open chat',
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
                                              tooltip: 'Start call',
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
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.call_outlined,
                                                      color:
                                                          AppColors.systemGreen,
                                                    ),
                                            ),
                                          ),
                                          Semantics(
                                            label: AccessibilityIds.startVideoCall,
                                            button: true,
                                            excludeSemantics: true,
                                            child: IconButton(
                                              tooltip: 'Start video call',
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
                                            tooltip: 'More options',
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

/// Tiny icon next to a contact's name in the grid.
class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.status});

  final ContactVerificationStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.hasMismatch) {
      return const Tooltip(
        message: 'Safety number changed since verification — re-verify',
        child: Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: AppColors.systemOrange,
        ),
      );
    }
    if (status.verified) {
      return const Tooltip(
        message: 'Safety number verified',
        child: Icon(
          Icons.verified_user,
          size: 16,
          color: AppColors.systemGreen,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
