import 'package:flutter/material.dart';

import '../../../../logging/log_buffer.dart';
import '../../../../logging/logger.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class LogEntryTile extends StatelessWidget {
  const LogEntryTile({super.key, required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    final levelColor = _colorFor(entry.level);
    final hh = entry.timestampUtc.hour.toString().padLeft(2, '0');
    final mm = entry.timestampUtc.minute.toString().padLeft(2, '0');
    final ss = entry.timestampUtc.second.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TgSpacing.md,
        vertical: TgSpacing.xs,
      ),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Text(
                '$hh:$mm:$ss',
                style: TgTypography.caption1.copyWith(
                  color: c.gray,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: TgSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.level.name.toUpperCase(),
                style: TgTypography.caption2Emphasis.copyWith(
                  color: levelColor,
                ),
              ),
            ),
            const SizedBox(width: TgSpacing.xs),
            Expanded(
              child: SelectableText.rich(
                TextSpan(
                  style: TgTypography.caption1,
                  children: [
                    TextSpan(text: entry.message),
                    if (entry.extrasText != null)
                      TextSpan(
                        text: entry.extrasText,
                        style: TgTypography.caption1.copyWith(
                          color: c.gray,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _colorFor(LogLevel level) {
  switch (level) {
    case LogLevel.debug:
      return c.gray;
    case LogLevel.info:
      return c.primary;
    case LogLevel.warn:
      return c.warning;
    case LogLevel.error:
      return c.error;
  }
}
