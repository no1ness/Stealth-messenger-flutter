/// Returns up to two uppercase initials for [value] — first letter of
/// the first word + first letter of the second word (if present).
/// Falls back to `'?'` for null / empty / whitespace-only input.
///
/// Extracted from `chats_screen.dart` (FIX_PLAN Phase B).
String nameInitials(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '?';
  }

  final parts = value.trim().split(RegExp(r'\s+'));
  final first = parts.first.isNotEmpty ? parts.first[0] : '';
  final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
  return (first + second).toUpperCase();
}
