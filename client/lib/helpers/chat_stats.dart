/// Sums `unreadCount` across a list of chat-row maps. Extracted from
/// `chats_screen.dart` (FIX_PLAN Phase B); kept generic enough to feed
/// any future surface that needs the same rollup (e.g. settings badge).
int totalUnreadCount(List<Map<String, dynamic>> chats) {
  return chats.fold<int>(
    0,
    (sum, chat) => sum + (chat['unreadCount'] as int? ?? 0),
  );
}
