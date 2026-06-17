import 'package:intl/intl.dart';

/// Relative day-bucket formatting for chat-list timestamps. Renders the
/// time-of-day for "today", the string `"Yesterday"` for `diff == 1`,
/// and a full `dd.MM.yyyy` date otherwise.
///
/// Extracted from `chats_screen.dart` (FIX_PLAN Phase B).
String formatTimestamp(DateTime dateTime) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final diffDays = today.difference(thatDay).inDays;

  if (diffDays == 0) {
    return DateFormat('HH:mm').format(dateTime);
  }
  if (diffDays == 1) {
    return 'Вчера';
  }
  return DateFormat('dd.MM.yyyy').format(dateTime);
}

/// Parses an ISO-8601 string into local time and renders `HH:mm`.
/// Returns the empty string for null/invalid input — matches the
/// fallback the call sites already expect.
String formatMessageTime(String? value) {
  final parsed = DateTime.tryParse(value ?? '')?.toLocal();
  return parsed == null ? '' : DateFormat('HH:mm').format(parsed);
}
