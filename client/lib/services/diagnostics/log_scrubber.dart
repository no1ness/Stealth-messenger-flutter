// Inline content scrubber for the diagnostics report exporter.
//
// `Logger` redacts sensitive identifiers only when they live in the
// `extras` map under one of the known keys (see `_sensitiveKeys` in
// `lib/logging/logger.dart`). Identifiers interpolated *inside* the
// message text (e.g. `Logger.warn('chat $userId failed')`) bypass that
// guarantee.
//
// The diagnostics screen exports raw log lines to system share intents
// (Telegram, mail, ...), so it MUST scrub inline identifiers — otherwise
// users would leak UUIDs, PocketBase ids, and base64 public keys to
// third-party messengers when they tap "Share logs".
//
// This module is intentionally pattern-based and best-effort: it covers
// the formats actively used in this codebase. Cryptographic-strength
// scrubbing is out of scope.

/// UUID v4: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (lowercase hex with
/// dashes). Matches the local `userId` shape (see `IdentityService`).
final RegExp _uuidPattern = RegExp(
  r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
);

/// PocketBase record id: 15-char alphanumeric (see `pb_user_id.dart`,
/// SHA-256 truncated). The heuristic filter — requires at least one
/// digit AND at least one letter — keeps natural-language words of the
/// same length (`notification123`, `xxxxxxxxxxxxxxx`) from matching too
/// aggressively. Word-boundary anchored so it won't eat substrings.
final RegExp _pbIdPattern = RegExp(r'\b[0-9a-z]{15}\b');

/// Base64-ish ed25519/X25519 public key. 32 raw bytes → 43-char base64
/// (no padding) or 44 with `=` padding. We also accept the URL-safe
/// variant (`-`, `_`). The heuristic filter — must mix letter cases AND
/// contain at least one digit — significantly reduces matches on long
/// natural words while still catching real keys.
final RegExp _base64KeyPattern =
    RegExp(r'\b[A-Za-z0-9+/_\-]{42,44}={0,2}\b');

/// Replaces an entire matched run with the tail-only marker
/// `…<last-4-chars-without-padding>`. The four-character tail matches
/// `Logger.redactId` style.
String _redactMatch(Match m) {
  final raw = m.group(0)!;
  final trimmed = raw.replaceAll('=', '');
  if (trimmed.length <= 4) return '…';
  return '…${trimmed.substring(trimmed.length - 4)}';
}

bool _pbIdHeuristicOk(String value) {
  // Skip if the candidate is all letters or all digits — real PB ids
  // mix both.
  final hasDigit = value.contains(RegExp(r'[0-9]'));
  final hasLetter = value.contains(RegExp(r'[a-z]'));
  return hasDigit && hasLetter;
}

bool _base64KeyHeuristicOk(String value) {
  // Real base64-encoded random bytes mix upper, lower, digits.
  final hasDigit = value.contains(RegExp(r'[0-9]'));
  final hasUpper = value.contains(RegExp(r'[A-Z]'));
  final hasLower = value.contains(RegExp(r'[a-z]'));
  return hasDigit && hasUpper && hasLower;
}

/// Returns [line] with any inline UUID / PocketBase id / base64 public
/// key replaced by `…XXXX`.
///
/// Idempotent: `scrubInlineSensitive(scrubInlineSensitive(x))` equals
/// `scrubInlineSensitive(x)` — the marker `…XXXX` doesn't itself match
/// any pattern.
String scrubInlineSensitive(String line) {
  if (line.isEmpty) return line;
  // UUID first — strictly shaped, never a false positive.
  var result = line.replaceAllMapped(_uuidPattern, _redactMatch);
  // Base64-shaped keys next — longer matches first reduce risk that a
  // 15-char PB id inside a 43-char base64 chunk gets eaten by the
  // shorter rule.
  result = result.replaceAllMapped(_base64KeyPattern, (m) {
    return _base64KeyHeuristicOk(m.group(0)!) ? _redactMatch(m) : m.group(0)!;
  });
  // PocketBase id last.
  result = result.replaceAllMapped(_pbIdPattern, (m) {
    return _pbIdHeuristicOk(m.group(0)!) ? _redactMatch(m) : m.group(0)!;
  });
  return result;
}
