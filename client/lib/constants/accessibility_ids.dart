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
}
