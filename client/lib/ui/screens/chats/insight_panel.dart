import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../themes/apple_liquid/constants/app_colors.dart';

/// Right-rail dashboard with session insights (realtime sync / platform
/// / current user marker) and a tiny animated bar chart.
///
/// Stateless — all input is passed as props by the parent
/// [ChatsScreen]. Extracted from `chats_screen.dart` as task #14 of the
/// post-PocketBase hardening plan
/// (`.ai-factory/plans/client-hardening-followup.md`).
class InsightPanel extends StatelessWidget {
  const InsightPanel({
    super.key,
    required this.messageCount,
    required this.visibleChatCount,
    required this.myUserId,
  });

  final int messageCount;
  final int visibleChatCount;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [
      messageCount == 0 ? 0.18 : 0.68,
      visibleChatCount == 0 ? 0.12 : 0.54,
      kIsWeb ? 0.74 : 0.49,
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session insight', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const _InsightTile(
            label: 'Realtime sync',
            value: 'Active',
            accent: AppColors.systemGreen,
          ),
          const SizedBox(height: 10),
          _InsightTile(
            label: 'Platform',
            value: kIsWeb ? 'Web' : 'Mobile',
            accent: AppColors.systemBlue,
          ),
          const SizedBox(height: 10),
          _InsightTile(
            label: 'Current user',
            value: myUserId == null ? 'Unknown' : myUserId!.substring(0, 8),
            accent: AppColors.systemOrange,
          ),
          const SizedBox(height: 22),
          Text('Load profile', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values
                  .map(
                    (value) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          height: 110 * value,
                          decoration: BoxDecoration(
                            color: AppColors.systemBlue.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
