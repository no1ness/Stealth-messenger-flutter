/// Maps a file name to a coarse-grained attachment category used by the
/// chat UI. Extension-based heuristic — no mime-sniffing. Returns
/// `'image' | 'audio' | 'file'`.
///
/// Extracted from `chats_screen.dart` (FIX_PLAN Phase B) so the
/// classifier can be reused by future attachment surfaces (e.g. group
/// management sheet, message editor) without dragging in the screen's
/// stateful machinery.
String resolveAttachmentType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp')) {
    return 'image';
  }
  if (lower.endsWith('.m4a') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.ogg')) {
    return 'audio';
  }
  return 'file';
}
