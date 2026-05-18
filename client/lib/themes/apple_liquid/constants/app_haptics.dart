/// Semantic haptic intensities for the Stealth design system.
///
/// The mapping from intent → platform `HapticFeedback.*` call lives
/// inside `client/lib/themes/apple_liquid/feedback/stealth_haptics.dart`.
/// This enum is the public-facing vocabulary that widgets use to
/// request feedback without having to know which platform call it
/// triggers.
///
/// Why an enum instead of calling `HapticFeedback.lightImpact` etc.
/// directly:
///
/// - The compound patterns (`success` = medium → light,
///   `error` = heavy × 2) are not expressible as a single SDK call;
///   they need [StealthHaptics] to sequence them.
/// - Web has no haptics — [StealthHaptics] no-ops there.
///   Routing through the enum means widgets don't have to know.
/// - Accessibility "reduce motion" should silence haptics too
///   (haptics are part of motion). [StealthHaptics] handles that
///   gating centrally.
enum HapticIntensity {
  /// Lightest tap. Send-message confirmation, list-item selection,
  /// toggle switch flip. Most-used intensity in the app.
  light,

  /// Medium tap. Call dial, dialog open, theme switch confirmation,
  /// voice-record start.
  medium,

  /// Strong tap. Call hangup, destructive-action confirmation
  /// (logout, delete, reset).
  heavy,

  /// Compound success pattern (medium → light). Nickname saved,
  /// message delivered, key rotation completed.
  success,

  /// Compound warn pattern (heavy → light). Recoverable issue —
  /// network blip, queued retry, transient permission denial.
  warn,

  /// Compound error pattern (heavy × 2). Unrecoverable issue —
  /// auth failed, decryption failed, connection lost during call.
  error,

  /// Picker-style selection tick. Used for segmented control
  /// changes (theme toggle), tab swipes, list scrubbing.
  selection,
}
