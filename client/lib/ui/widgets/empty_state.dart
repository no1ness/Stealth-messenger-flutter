import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final String type;

  const EmptyState({super.key, required this.type});

  String _getTitle() {
    switch (type) {
      case 'chats':
        return 'No chats yet';
      case 'contacts':
        return 'No contacts yet';
      default:
        return 'Nothing to see here';
    }
  }

  String _getDescription() {
    switch (type) {
      case 'chats':
        return 'Start a new conversation to see it here.';
      case 'contacts':
        return 'Add a new contact to start chatting.';
      default:
        return '';
    }
  }

  IconData _getIcon() {
    switch (type) {
      case 'chats':
        return Icons.chat_bubble_outline;
      case 'contacts':
        return Icons.person_add_alt_1_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIcon(),
              size: 80,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              _getTitle(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.8),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _getDescription(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
