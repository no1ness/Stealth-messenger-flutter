import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/themes/apple_liquid/components/glass_container.dart';
import 'package:stealth/themes/apple_liquid/constants/app_colors.dart';
import 'package:stealth/themes/apple_liquid/constants/app_spacing.dart';
import 'package:stealth/themes/apple_liquid/constants/app_typography.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_app_bar.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_text_field.dart';
import 'package:stealth/ui/screens/chats_screen.dart';
import 'package:stealth/ui/screens/webrtc_call_screen.dart';
import 'package:stealth/webrtc_support.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addContactController = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  bool _loading = true;
  bool _startingCall = false;
  List<Map<String, dynamic>> _contacts = const [];

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
    final rows = await _supabaseService.getContacts();
    if (!mounted) {
      return;
    }

    setState(() {
      _contacts = rows.cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _deleteContact(Map<String, dynamic> contact) async {
    final userId = contact['user_id'] as String?;
    final name = contact['name'] as String? ?? 'Contact';
    if (userId == null || userId.isEmpty) {
      return;
    }

    await _supabaseService.deleteContact(userId);
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
    if (userId == null) return;

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Generating fingerprint...'),
            ],
          ),
        ),
      );
    }

    final safetyNumber = await _supabaseService.getSafetyNumber(userId);
    
    if (mounted) {
      Navigator.of(context).pop(); // Закрываем диалог загрузки
      
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Safety Number - $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Compare this number with your contact. If it matches exactly, your end-to-end encryption is secure and no one can intercept your chats.',
                style: AppTypography.caption1.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                safetyNumber ?? 'Error generating number',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontFamily: 'Courier',
                  color: AppColors.systemBlue,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
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
              final rows = await _supabaseService.searchUsers(
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
                  TextField(
                    controller: _addContactController,
                    decoration: const InputDecoration(
                      hintText: 'Search by nickname or full user ID',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => search(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Tip: open Profile on the other device and copy its User ID for exact search.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: pasteAndSearch,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Paste ID'),
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
                                trailing: FilledButton(
                                  onPressed: () async {
                                    await _supabaseService.addContact(
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

    final chatId = await _supabaseService.findOrCreatePrivateChatWith(userId);
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

    final chatId = await _supabaseService.findOrCreatePrivateChatWith(userId);
    if (!mounted || chatId == null) {
      if (mounted) {
        setState(() => _startingCall = false);
      }
      return;
    }

    await _supabaseService.sendCallInitiation(
      chatId: chatId,
      isVideoCall: isVideoCall,
    );
    if (!mounted) {
      return;
    }

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
                  child: FilledButton.icon(
                    onPressed: _showAddContactSheet,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add contact'),
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
                                    child: Text(
                                      'No contacts found',
                                      style: AppTypography.body.copyWith(
                                        color: AppColors.textSecondary,
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
                                itemBuilder: (context, index) {
                                  final contact = filtered[index];
                                  return InkWell(
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
                                                Text(
                                                  (contact['name'] as String?) ??
                                                      'Unknown',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      AppTypography.body.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
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
                                            onPressed: _startingCall
                                                ? null
                                                : () => _openChat(contact),
                                            icon: const Icon(
                                              Icons.chat_bubble_outline,
                                              color: AppColors.systemBlue,
                                            ),
                                          ),
                                          IconButton(
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
                                          IconButton(
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
                                          IconButton(
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
