import 'package:flutter/material.dart';
import 'package:stealth/main_tabs.dart';
import 'package:stealth/themes/apple_liquid/widgets/circuit_board_background.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, this.initialChatId});

  final String? initialChatId;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  final List<String> _steps = const [
    'Initializing secure session',
    'Loading chats',
    'Preparing adaptive interface',
  ];
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // A short deterministic sequence keeps launch behavior stable in every target.
    for (var index = 0; index < _steps.length; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) {
        return;
      }

      setState(() {
        _currentStep = index;
      });
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainTabs(initialChatId: widget.initialChatId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CircuitBoardBackground(
        animated: true,
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.security_rounded, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'STEALTH',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: (_currentStep + 1) / _steps.length,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _steps[_currentStep],
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
