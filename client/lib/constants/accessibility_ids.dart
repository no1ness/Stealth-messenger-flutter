/// Accessibility ID constants for Appium/UiAutomator2 test automation.
///
/// These labels are the single source of truth for all [Semantics] wrappers
/// across the app. Do NOT change values without updating the Appium test suite.
class AccessibilityIds {
  AccessibilityIds._();

  // Navigation tabs
  static const String chatsTab = 'Chats';
  static const String contactsTab = 'Contacts';
  static const String profileTab = 'Profile';
  static const String settingsTab = 'Settings';

  // Contacts screen
  static const String addContact = 'Add contact';
  static const String startCall = 'Start call';
  static const String startVideoCall = 'Start video call';
  static const String contactBundleInput = 'Contact bundle input';
  static const String saveContact = 'Save contact';

  // Call screen
  static const String answer = 'Answer';
  static const String decline = 'Decline';
  static const String hangUp = 'Hang up';
  static const String mute = 'Mute';
  static const String speaker = 'Speaker';
  static const String callStatus = 'Call status';
  static const String callerName = 'Caller name';

  // Chats screen
  static const String messageInput = 'Message input';
  static const String sendMessage = 'Send message';
  static const String attachFile = 'Attach file';

  // Profile screen
  static const String userId = 'User ID';
  static const String username = 'Username';
  static const String copyContactBundle = 'Copy contact bundle';
  static const String logout = 'Logout';

  // Dynamic helpers
  static String contact(String name) => 'Contact $name';
  static String chat(String name) => 'Chat $name';

  // --------------------------------------------------------------
  // Design-system v2 additions — extracted widgets and new surfaces
  // introduced by the UI refactor (see
  // .ai-factory/plans/feature-ui-design-refactor.md). Any change to
  // a value below MUST be mirrored in the Appium suite.
  // --------------------------------------------------------------

  // ChatTile (extracted from chats_screen)
  static const String chatTileAvatar = 'Chat avatar';
  static const String chatTileLastMessage = 'Chat last message';
  static const String chatTileUnreadBadge = 'Chat unread count';

  // ContactTile (extracted from contacts_screen)
  static const String contactTileTrailing = 'Contact actions';
  static const String contactTileVerificationBadge = 'Verification status';

  // Section structure
  static const String sectionHeader = 'Section header';
  static const String listDivider = 'List divider';

  // Feedback helpers (StealthSnackBar / StealthDialog)
  static const String snackBarMessage = 'Notification message';
  static const String snackBarDismiss = 'Dismiss notification';
  static const String dialogPrimaryAction = 'Confirm';
  static const String dialogSecondaryAction = 'Cancel';
  static const String dialogDestructiveAction = 'Confirm destructive';

  // Settings theme toggle
  static const String themeToggleSegmented = 'Theme mode';
  static const String themeToggleLight = 'Light theme';
  static const String themeToggleDark = 'Dark theme';
  static const String themeToggleSystem = 'System theme';

  // Call HUD (Phase 7)
  static const String callEncryptedBadge = 'E2E encrypted indicator';
  static const String callDurationTimer = 'Call duration';
  static const String callConnectionStatus = 'Connection status';
}
