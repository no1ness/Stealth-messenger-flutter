import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_text_field.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../components/glass_container.dart';

class LiquidContactsScreen extends StatefulWidget {
  const LiquidContactsScreen({super.key});

  @override
  State<LiquidContactsScreen> createState() => _LiquidContactsScreenState();
}

class _LiquidContactsScreenState extends State<LiquidContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseService _supabaseService = SupabaseService();
  bool _loading = true;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filteredContacts = [];

  @override
  void initState() {
    super.initState();
    _ensureDefaultContactsAndLoad();
  }

  Future<void> _ensureDefaultContactsAndLoad() async {
    // Ensure default contacts are added
    await _supabaseService.ensureDefaultUserContacts();
    // Then load contacts
    _loadContacts();
  }

  Future<void> _addDefaultContacts() async {
    try {
      await _supabaseService.ensureDefaultContacts();
      await _supabaseService.addDefaultUserContacts(); // Use the force add method
      await _loadContacts();
      if (mounted) {
        // Show a snackbar or other notification that contacts were added
        // Since this is a different theme, we'll just reload the contacts
      }
    } catch (e) {
      debugPrint('Error adding default contacts: $e');
    }
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    try {
      final contacts = await _supabaseService.fetchContacts();
      if (!mounted) return;
      
      final contactsList = <Map<String, dynamic>>[];
      for (final contact in contacts) {
        contactsList.add({
          'id': contact['contact_user_id'] ?? contact['id'],
          'nickname': contact['name'] ?? 'Unknown',
          'publicKey': '', // We don't have this in the contact list
          'status': 'offline',
        });
      }
      
      setState(() {
        _contacts = contactsList;
        _filteredContacts = contactsList;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _filterContacts(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredContacts = _contacts;
      });
      return;
    }
    
    setState(() {
      _filteredContacts = _contacts
          .where((contact) =>
              contact['nickname'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _startChat(String contactId) async {
    try {
      final chatId = await _supabaseService.findOrCreatePrivateChatWith(contactId);
      if (!mounted) return;
      // Navigate to chat
      // Navigator.push(...);
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _showAddContactDialog() async {
    final qrDataController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add Contact',
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GlassTextField(
                controller: qrDataController,
                hintText: 'Enter User ID',
                labelText: 'User ID',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: GlassButton(
                      isPrimary: true,
                      onPressed: () async {
                        final userId = qrDataController.text.trim();
                        if (userId.isNotEmpty) {
                          try {
                            // For now, we'll just add a placeholder name
                            await _supabaseService.addContact(userId: userId, name: 'New Contact');
                            if (!mounted) return;
                            Navigator.pop(context);
                            await _loadContacts();
                          } catch (e) {
                            // Handle error
                          }
                        }
                      },
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundPrimary,
              AppColors.backgroundSecondary,
              AppColors.backgroundPrimary,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Contacts',
                          style: AppTypography.largeTitle.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _addDefaultContacts,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: AppColors.liquidGradient1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.refresh,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            GestureDetector(
                              onTap: _showAddContactDialog,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: AppColors.liquidGradient1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GlassSearchField(
                      controller: _searchController,
                      hintText: 'Search contacts',
                      onChanged: _filterContacts,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredContacts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 64,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'No contacts yet',
                                  style: AppTypography.body.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            itemCount: _filteredContacts.length,
                            itemBuilder: (context, index) {
                              final contact = _filteredContacts[index];
                              return _buildContactItem(contact);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactItem(Map<String, dynamic> contact) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      onTap: () => _startChat(contact['id']),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.liquidGradient2,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                contact['nickname'][0].toUpperCase(),
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact['nickname'],
                  style: AppTypography.headline.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: contact['status'] == 'online'
                            ? AppColors.systemGreen
                            : AppColors.systemGray,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      contact['status'],
                      style: AppTypography.caption1.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.message,
              color: AppColors.systemBlue,
            ),
            onPressed: () => _startChat(contact['id']),
          ),
        ],
      ),
    );
  }
}
