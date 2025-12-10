import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/themes/apple_liquid/widgets/circuit_board_background.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  String _statusText = 'Initializing...';
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
    _loadData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final supabaseService = SupabaseService();
    
    try {
      // Step 1: Check user
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => _statusText = 'Loading chats...');
      
  // Step 2: Ensure default test contacts and private chats exist and preload chats
  await supabaseService.ensureDefaultContacts();
  await supabaseService.ensureDefaultPrivateChats();
  await supabaseService.ensureDefaultUserContacts(); // Ensure default contacts are added to user's contact list
  // DEBUG: force-create the known test contacts and log results (helps validate DB migration)
  try {
    final okPoco = await supabaseService.debugCreateContactById(contactUserId: '11111111-1111-1111-1111-111111111111', name: 'POCO');
    final okGeekom = await supabaseService.debugCreateContactById(contactUserId: '22222222-2222-2222-2222-222222222222', name: 'GEEKOM');
    debugPrint('DEBUG: POCO added=$okPoco GEEKOM added=$okGeekom');
  } catch (e) {
    debugPrint('DEBUG: error while debugCreateContactById: $e');
  }
  await supabaseService.fetchChats();
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      setState(() => _statusText = 'Loading contacts...');
      
      // Step 3: Preload contacts
      await supabaseService.fetchContacts();
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      setState(() => _statusText = 'Almost ready...');
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Navigate to main tabs and optionally open default chat (POCO on web, GEEKOM on mobile)
      if (!mounted) return;
      String? initialChatId;
      try {
        final isWeb = identical(0, 0.0); // dummy to allow replacement at compile-time
        // Use kIsWeb import via runtime check by trying to access MediaQuery? Simpler: use Uri.base to detect web
        final bool runningOnWeb = Uri.base.scheme == 'http' || Uri.base.scheme == 'https';
        final partnerId = runningOnWeb
            ? '11111111-1111-1111-1111-111111111111' // POCO on web
            : '22222222-2222-2222-2222-222222222222'; // GEEKOM on mobile
        initialChatId = await supabaseService.findOrCreatePrivateChatWith(partnerId);
      } catch (e) {
        debugPrint('Error determining initial chatId: $e');
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainTabs(initialChatId: initialChatId)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = 'Error loading data. Retrying...');
      await Future.delayed(const Duration(seconds: 2));
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CircuitBoardBackground(
        animated: true,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset(
                      'assets/STEALTH.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Icon(
                            Icons.lock_outline,
                            size: 60,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                
                // Welcome text
                Text(
                  'Welcome to',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stealth Messenger',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 60),
                
                // Loading indicator
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Status text
                Text(
                  _statusText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
