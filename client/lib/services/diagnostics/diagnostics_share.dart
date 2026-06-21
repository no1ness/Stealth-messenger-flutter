// System share intent integration for the diagnostics report.
//
// Used by the in-app diagnostics screen's "Share logs" button. Hands the
// report to the native share sheet on Android/iOS via a temporary .txt
// file (matches expectations of mail/Telegram apps), or to the Web Share
// API on web (no file). On any failure or user-dismiss, falls back to
// the clipboard so the user can still paste the report manually.

import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../logging/logger.dart';
import '../../themes/tg/tg_colors.dart';

/// Possible outcomes returned by [shareDiagnosticsReport]. Exposed for
/// widget tests so they can assert which branch was hit by a fake invoker.
enum ShareOutcome { shared, dismissed, copiedToClipboard, failed }

/// Function signature for "deliver this text to the user somehow". Used
/// as the type of the `shareInvoker` parameter on `DiagnosticsScreen` so
/// tests can substitute a fake without touching native plugins.
typedef ShareInvoker = Future<ShareOutcome> Function(
  BuildContext context,
  String reportText,
);

/// Production [ShareInvoker]. Tries native share first, falls back to
/// clipboard + SnackBar on any failure.
Future<ShareOutcome> shareDiagnosticsReport(
  BuildContext context,
  String reportText,
) async {
  final ts = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final preview = _previewOf(reportText);

  try {
    if (kIsWeb) {
      // No filesystem on web — hand the text straight to Web Share API.
      Logger.info('[diag.share] share intent invoked');
      final result = await SharePlus.instance.share(
        ShareParams(text: reportText, subject: 'Stealth diagnostics $ts'),
      );
      if (!context.mounted) return _outcomeFromStatusNoContext(result);
      return _outcomeFromStatus(result, context, reportText);
    }

    final dir = await getTemporaryDirectory();
    await _cleanupOldReports(dir);
    final file = File('${dir.path}/stealth-diagnostics-$ts.txt');
    await file.writeAsString(reportText);
    Logger.debug('[diag.share] tmp file written', extras: {
      'path': file.path,
      'bytes': reportText.length,
    });

    Logger.info('[diag.share] share intent invoked');
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'Stealth diagnostics $ts',
        text: preview,
      ),
    );
    if (!context.mounted) return _outcomeFromStatusNoContext(result);
    return _outcomeFromStatus(result, context, reportText);
  } catch (error) {
    Logger.error('[diag.share] failed', extras: {'error': error});
    if (!context.mounted) return ShareOutcome.failed;
    return _fallbackToClipboard(context, reportText);
  }
}

ShareOutcome _outcomeFromStatusNoContext(ShareResult result) {
  switch (result.status) {
    case ShareResultStatus.success:
      return ShareOutcome.shared;
    case ShareResultStatus.dismissed:
      return ShareOutcome.dismissed;
    case ShareResultStatus.unavailable:
      return ShareOutcome.failed;
  }
}

ShareOutcome _outcomeFromStatus(
  ShareResult result,
  BuildContext context,
  String reportText,
) {
  switch (result.status) {
    case ShareResultStatus.success:
      return ShareOutcome.shared;
    case ShareResultStatus.dismissed:
      Logger.warn('[diag.share] dismissed by user');
      return ShareOutcome.dismissed;
    case ShareResultStatus.unavailable:
      Logger.warn('[diag.share] platform reported unavailable');
      return _fallbackToClipboardSync(context, reportText);
  }
}

ShareOutcome _fallbackToClipboardSync(
  BuildContext context,
  String reportText,
) {
  unawaited(_fallbackToClipboard(context, reportText));
  return ShareOutcome.copiedToClipboard;
}

Future<ShareOutcome> _fallbackToClipboard(
  BuildContext context,
  String reportText,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: reportText));
    if (context.mounted) {
      showStealthSnackBar(context, 'Диагностика скопирована');
    }
    return ShareOutcome.copiedToClipboard;
  } catch (error) {
    Logger.error('[diag.share] clipboard fallback failed',
        extras: {'error': error});
    return ShareOutcome.failed;
  }
}

/// First three lines of the report, used as the preview text the share
/// sheet shows alongside the file attachment.
String _previewOf(String report) {
  final newlines = <int>[];
  for (var i = 0; i < report.length && newlines.length < 3; i++) {
    if (report.codeUnitAt(i) == 0x0a) newlines.add(i);
  }
  if (newlines.length < 3) return report;
  return report.substring(0, newlines[2]);
}

Future<void> _cleanupOldReports(Directory dir) async {
  try {
    await for (final entity in dir.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('stealth-diagnostics-')) {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort; ignore individual deletion failures.
        }
      }
    }
  } catch (error) {
    Logger.debug('[diag.share] tmp cleanup skipped', extras: {'error': error});
  }
}
