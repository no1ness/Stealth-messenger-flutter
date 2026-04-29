# Design Document: Appium Accessibility Support

## Overview

This design implements Flutter Semantics widgets across the Stealth Messenger application to enable Appium-based automated testing on Android devices. The implementation wraps key UI elements with accessibility metadata without altering visual appearance or layout.

### Goals

- Enable Appium element discovery through UiAutomator2 on Android
- Maintain zero visual impact on end-user experience
- Provide consistent accessibility IDs across all screens
- Support existing Appium test infrastructure without additional configuration

### Non-Goals

- iOS accessibility support (out of scope for this feature)
- Screen reader optimization for visually impaired users
- Dynamic or localized accessibility labels
- Accessibility for web version (CanvasKit rendering limitations)

### Key Design Decisions

**Decision 1: Use Flutter Semantics Widget**
- Rationale: Native Flutter API that exposes metadata to platform accessibility services
- Alternative considered: Custom test IDs through platform channels (rejected due to complexity)
- Trade-off: Semantics adds minimal overhead but provides standard integration

**Decision 2: English-only Accessibility IDs**
- Rationale: Test automation requires stable, language-independent identifiers
- Alternative considered: Localized labels (rejected due to test maintenance burden)
- Trade-off: Accessibility IDs won't match UI language, but tests remain stable

**Decision 3: Wrap Existing Widgets, Don't Rebuild**
- Rationale: Minimize code changes and preserve existing behavior
- Alternative considered: Rebuild widgets with built-in semantics (rejected due to scope)
- Trade-off: Slightly more verbose code, but safer and faster to implement

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter Application                   │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │           UI Widgets (Existing)                    │ │
│  │  - Navigation Tabs                                 │ │
│  │  - Contact List                                    │ │
│  │  - Chat List                                       │ │
│  │  - Call Controls                                   │ │
│  │  - Profile Information                             │ │
│  └────────────────────────────────────────────────────┘ │
│                         ↓                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │      Semantics Wrapper Layer (NEW)                │ │
│  │  - Semantics(label: "Contacts", child: ...)       │ │
│  │  - Semantics(label: "Start call", child: ...)     │ │
│  │  - Semantics(label: "User ID", child: ...)        │ │
│  └────────────────────────────────────────────────────┘ │
│                         ↓                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Flutter Semantics Tree                     │ │
│  │  (Internal representation of accessibility data)   │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│              Android Accessibility Service               │
│  (Exposes semantics to UiAutomator2)                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                  Appium + UiAutomator2                   │
│  - driver.$('~Contacts')                                │
│  - driver.$('~Start call').click()                      │
│  - driver.$('~User ID').getText()                       │
└─────────────────────────────────────────────────────────┘
```

### Integration Points

1. **main_tabs.dart**: Navigation tab buttons
2. **contacts_screen.dart**: Contact list items, call buttons, add contact button
3. **chats_screen.dart**: Chat list items, message input, send button
4. **webrtc_call_screen_native_impl.dart**: Call control buttons, status indicators
5. **profile_screen.dart**: User ID display, username display, action buttons

### Data Flow

1. Developer wraps widget with `Semantics(label: "...", child: Widget)`
2. Flutter builds semantics tree alongside widget tree
3. Android Accessibility Service reads semantics tree
4. UiAutomator2 exposes elements with `content-desc` attribute
5. Appium locates elements using `~AccessibilityID` selector
6. Test automation interacts with elements (tap, input, getText)

## Components and Interfaces

### Semantics Wrapper Pattern

All accessibility implementations follow this pattern:

```dart
Semantics(
  label: 'Accessibility ID',  // English, stable identifier
  button: true,               // Optional: marks as tappable
  enabled: true,              // Optional: marks as interactive
  child: ExistingWidget(),
)
```

### Component 1: Navigation Tabs (main_tabs.dart)

**Location**: `client/lib/main_tabs.dart`

**Modification**: Wrap `GlassBottomNavBarItem` widgets with Semantics

**Implementation**:

```dart
bottomNavigationBar: GlassBottomNavBar(
  currentIndex: _currentIndex,
  onTap: (index) {
    setState(() {
      _currentIndex = index;
    });
  },
  items: [
    GlassBottomNavBarItem(
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      label: 'Chats',
      // Semantics will be added in GlassBottomNavBar implementation
    ),
    // ... other items
  ],
)
```

**Alternative**: Modify `GlassBottomNavBar` widget to automatically wrap items with Semantics based on label property.

**Accessibility IDs**:
- `Chats` - Chats tab button
- `Contacts` - Contacts tab button
- `Profile` - Profile tab button
- `Settings` - Settings tab button

### Component 2: Contact List (contacts_screen.dart)

**Location**: `client/lib/ui/screens/contacts_screen.dart`

**Modification**: Wrap contact cards and action buttons with Semantics

**Implementation Example**:

```dart
// Contact card wrapper
Semantics(
  label: 'Contact ${contact['name']}',
  button: true,
  enabled: true,
  child: ListTile(
    // existing contact card implementation
  ),
)

// Call button wrapper
Semantics(
  label: 'Start call',
  button: true,
  enabled: true,
  child: IconButton(
    icon: const Icon(Icons.call),
    onPressed: () => _startCall(contact, isVideoCall: false),
  ),
)

// Add contact button
Semantics(
  label: 'Add contact',
  button: true,
  enabled: true,
  child: FloatingActionButton(
    // existing implementation
  ),
)
```

**Accessibility IDs**:
- `Contact {name}` - Individual contact card (dynamic based on contact name)
- `Start call` - Audio call button
- `Start video call` - Video call button
- `Add contact` - Add new contact button
- `Contact ID input` - Contact ID input field (in add dialog)
- `Contact name input` - Contact name input field (in add dialog)
- `Save contact` - Save button in add dialog
- `Cancel` - Cancel button in add dialog

### Component 3: Chat List (chats_screen.dart)

**Location**: `client/lib/ui/screens/chats_screen.dart`

**Modification**: Wrap chat list items and message controls with Semantics

**Implementation Example**:

```dart
// Chat list item wrapper
Semantics(
  label: 'Chat ${chat['name']}',
  button: true,
  enabled: true,
  child: ListTile(
    // existing chat item implementation
  ),
)

// Message input wrapper
Semantics(
  label: 'Message input',
  textField: true,
  enabled: true,
  child: TextField(
    // existing message input implementation
  ),
)

// Send button wrapper
Semantics(
  label: 'Send message',
  button: true,
  enabled: true,
  child: IconButton(
    icon: const Icon(Icons.send),
    onPressed: _sendMessage,
  ),
)
```

**Accessibility IDs**:
- `Chat {name}` - Individual chat item (dynamic based on chat name)
- `Message input` - Message text input field
- `Send message` - Send message button
- `Attach file` - File attachment button

### Component 4: WebRTC Call Screen (webrtc_call_screen_native_impl.dart)

**Location**: `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`

**Modification**: Wrap call control buttons and status indicators with Semantics

**Implementation Example**:

```dart
// Call status wrapper
Semantics(
  label: 'Call status',
  liveRegion: true,
  child: Text(
    _connected ? _formatDuration(_callDurationSeconds) : 
                 _initializing ? 'Connecting...' : 'Calling...',
  ),
)

// Hang up button wrapper
Semantics(
  label: 'Hang up',
  button: true,
  enabled: true,
  child: _buildControlButton(
    icon: Icons.call_end,
    color: AppColors.systemRed,
    iconColor: Colors.white,
    size: 72,
    onPressed: _hangUp,
  ),
)

// Mute button wrapper
Semantics(
  label: 'Mute',
  button: true,
  enabled: true,
  child: _buildControlButton(
    icon: _microphoneEnabled ? Icons.mic : Icons.mic_off,
    onPressed: _toggleMicrophone,
  ),
)

// Speaker button wrapper
Semantics(
  label: 'Speaker',
  button: true,
  enabled: true,
  child: _buildControlButton(
    icon: _speakerEnabled ? Icons.volume_up : Icons.volume_off,
    onPressed: _toggleSpeaker,
  ),
)
```

**Accessibility IDs**:
- `Call status` - Call status text (Connecting, Ringing, Connected, duration)
- `Caller name` - Caller identification (for incoming calls)
- `Answer` - Answer incoming call button
- `Decline` - Decline incoming call button
- `Hang up` - End call button
- `Mute` - Mute/unmute microphone button
- `Speaker` - Speaker on/off button

### Component 5: Profile Screen (profile_screen.dart)

**Location**: `client/lib/ui/screens/profile_screen.dart`

**Modification**: Wrap user information displays with Semantics

**Implementation Example**:

```dart
// User ID wrapper
Semantics(
  label: 'User ID',
  readOnly: true,
  child: Text(_userId ?? 'Loading...'),
)

// Username wrapper
Semantics(
  label: 'Username',
  readOnly: true,
  child: Text(_nickname ?? 'No nickname'),
)

// Copy User ID button wrapper
Semantics(
  label: 'Copy User ID',
  button: true,
  enabled: true,
  child: IconButton(
    icon: const Icon(Icons.copy),
    onPressed: _copyUserId,
  ),
)
```

**Accessibility IDs**:
- `User ID` - User ID display text
- `Username` - Username/nickname display text
- `Copy User ID` - Copy user ID button
- `Export Private Key` - Export key button
- `Logout` - Logout button

## Data Models

No new data models are required. This feature only adds metadata wrappers around existing UI components.

### Semantics Widget Properties

```dart
Semantics({
  String? label,           // Accessibility ID exposed to Appium
  bool button = false,     // Marks element as button
  bool textField = false,  // Marks element as text input
  bool enabled = true,     // Marks element as interactive
  bool readOnly = false,   // Marks element as non-editable
  bool liveRegion = false, // Marks element as dynamic content
  Widget? child,           // Wrapped widget
})
```

## Error Handling

### Error Scenario 1: Semantics Not Exposed to Appium

**Cause**: Android accessibility service disabled or Flutter semantics not enabled

**Detection**: Appium throws `NoSuchElementException` when querying by accessibility ID

**Handling**: 
- Document requirement for accessibility service to be enabled
- Provide diagnostic command: `adb shell settings get secure enabled_accessibility_services`
- No code changes needed (platform configuration issue)

### Error Scenario 2: Duplicate Accessibility IDs

**Cause**: Multiple widgets with same label on screen

**Detection**: Appium returns first matching element, tests may interact with wrong element

**Handling**:
- Use unique, descriptive labels (e.g., `Contact Alice` vs `Contact Bob`)
- For dynamic lists, include identifying information in label
- Document naming conventions in centralized reference

### Error Scenario 3: Accessibility ID Changes Between Versions

**Cause**: Developer modifies label text during refactoring

**Detection**: Existing Appium tests fail with `NoSuchElementException`

**Handling**:
- Establish naming convention and document all IDs
- Add code comments marking labels as test dependencies
- Consider creating constants file for accessibility IDs

**Example Constants File** (`lib/constants/accessibility_ids.dart`):

```dart
class AccessibilityIds {
  // Navigation
  static const String chatsTab = 'Chats';
  static const String contactsTab = 'Contacts';
  static const String profileTab = 'Profile';
  
  // Contacts
  static const String addContact = 'Add contact';
  static const String startCall = 'Start call';
  static const String startVideoCall = 'Start video call';
  
  // Calls
  static const String answer = 'Answer';
  static const String decline = 'Decline';
  static const String hangUp = 'Hang up';
  static const String mute = 'Mute';
  static const String speaker = 'Speaker';
  static const String callStatus = 'Call status';
  
  // Chats
  static const String messageInput = 'Message input';
  static const String sendMessage = 'Send message';
  static const String attachFile = 'Attach file';
  
  // Profile
  static const String userId = 'User ID';
  static const String username = 'Username';
  static const String copyUserId = 'Copy User ID';
  
  // Dynamic labels
  static String contact(String name) => 'Contact $name';
  static String chat(String name) => 'Chat $name';
}
```

## Testing Strategy

### Unit Tests

Unit tests will verify that Semantics widgets are properly attached to UI elements without altering visual behavior.

**Test Categories**:

1. **Semantics Presence Tests**: Verify each key UI element has Semantics wrapper
2. **Label Correctness Tests**: Verify accessibility labels match expected values
3. **Visual Regression Tests**: Verify no layout or appearance changes

**Example Unit Test** (contacts_screen_test.dart):

```dart
testWidgets('Contact card has accessibility label', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ContactsScreen(),
    ),
  );
  
  // Wait for contacts to load
  await tester.pumpAndSettle();
  
  // Find Semantics widget with expected label
  final semanticsFinder = find.bySemanticsLabel('Contact Alice');
  expect(semanticsFinder, findsOneWidget);
  
  // Verify it's marked as button
  final semantics = tester.getSemantics(semanticsFinder);
  expect(semantics.hasAction(SemanticsAction.tap), isTrue);
});
```

**Example Visual Regression Test**:

```dart
testWidgets('Semantics does not alter visual appearance', (tester) async {
  // Capture screenshot before Semantics
  final beforeImage = await captureScreenshot(tester);
  
  // Add Semantics wrapper
  await tester.pumpWidget(
    Semantics(
      label: 'Test Button',
      button: true,
      child: ElevatedButton(
        onPressed: () {},
        child: Text('Click Me'),
      ),
    ),
  );
  
  // Capture screenshot after Semantics
  final afterImage = await captureScreenshot(tester);
  
  // Compare images
  expect(afterImage, matchesGoldenFile('button_with_semantics.png'));
  expect(imagesAreIdentical(beforeImage, afterImage), isTrue);
});
```

### Integration Tests

Integration tests will use Appium to verify end-to-end accessibility functionality on real Android devices.

**Test Categories**:

1. **Element Discovery Tests**: Verify Appium can locate elements by accessibility ID
2. **Interaction Tests**: Verify Appium can interact with elements (tap, input, swipe)
3. **Call Flow Tests**: Verify complete call initiation and answer flow

**Example Appium Test** (appium-accessibility-test.mjs):

```javascript
describe('Accessibility Support', () => {
  it('should find navigation tabs by accessibility ID', async () => {
    const contactsTab = await driver.$('~Contacts');
    expect(await contactsTab.isDisplayed()).toBe(true);
    
    await contactsTab.click();
    await driver.pause(1000);
    
    // Verify navigation occurred
    const addContactButton = await driver.$('~Add contact');
    expect(await addContactButton.isDisplayed()).toBe(true);
  });
  
  it('should find and interact with call buttons', async () => {
    // Navigate to contacts
    await driver.$('~Contacts').click();
    await driver.pause(1000);
    
    // Find first contact's call button
    const callButton = await driver.$('~Start call');
    expect(await callButton.isDisplayed()).toBe(true);
    
    await callButton.click();
    await driver.pause(2000);
    
    // Verify call screen appeared
    const hangUpButton = await driver.$('~Hang up');
    expect(await hangUpButton.isDisplayed()).toBe(true);
  });
  
  it('should read User ID from profile', async () => {
    // Navigate to profile
    await driver.$('~Profile').click();
    await driver.pause(1000);
    
    // Read User ID
    const userIdElement = await driver.$('~User ID');
    const userId = await userIdElement.getText();
    
    expect(userId).toMatch(/^[a-f0-9-]{36}$/); // UUID format
  });
});
```

### Test Execution Requirements

- **Platform**: Android API 21+ (Lollipop and above)
- **Appium Version**: 2.0+
- **Driver**: UiAutomator2
- **Test Framework**: WebdriverIO or similar
- **Devices**: Physical device + emulator coverage

### Accessibility ID Reference Document

Create `docs/accessibility-ids.md` documenting all accessibility IDs:

```markdown
# Accessibility ID Reference

## Navigation
- `Chats` - Chats tab button
- `Contacts` - Contacts tab button
- `Profile` - Profile tab button
- `Settings` - Settings tab button

## Contacts Screen
- `Add contact` - Add new contact button
- `Contact {name}` - Contact card (dynamic)
- `Start call` - Audio call button
- `Start video call` - Video call button
- `Contact ID input` - Contact ID input field
- `Save contact` - Save contact button
- `Cancel` - Cancel button

## Call Screen
- `Call status` - Call status indicator
- `Caller name` - Caller identification
- `Answer` - Answer call button
- `Decline` - Decline call button
- `Hang up` - End call button
- `Mute` - Mute toggle button
- `Speaker` - Speaker toggle button

## Chats Screen
- `Chat {name}` - Chat list item (dynamic)
- `Message input` - Message text field
- `Send message` - Send button
- `Attach file` - Attachment button

## Profile Screen
- `User ID` - User ID display
- `Username` - Username display
- `Copy User ID` - Copy button
- `Export Private Key` - Export button
- `Logout` - Logout button
```

## Implementation Plan

### Phase 1: Core Navigation (1-2 hours)
1. Create `lib/constants/accessibility_ids.dart` constants file
2. Modify `main_tabs.dart` to wrap navigation tabs
3. Write unit tests for navigation semantics
4. Test with Appium on emulator

### Phase 2: Contacts Screen (2-3 hours)
1. Modify `contacts_screen.dart` to wrap contact cards and buttons
2. Handle dynamic contact names in labels
3. Write unit tests for contact semantics
4. Test contact interaction with Appium

### Phase 3: Call Screens (2-3 hours)
1. Modify `webrtc_call_screen_native_impl.dart` to wrap call controls
2. Add semantics for incoming call dialog (CallManager widget)
3. Write unit tests for call semantics
4. Test call flow with Appium (two devices)

### Phase 4: Chats Screen (2-3 hours)
1. Modify `chats_screen.dart` to wrap chat list and message controls
2. Handle dynamic chat names in labels
3. Write unit tests for chat semantics
4. Test messaging with Appium

### Phase 5: Profile Screen (1-2 hours)
1. Modify `profile_screen.dart` to wrap user information
2. Write unit tests for profile semantics
3. Test profile reading with Appium

### Phase 6: Documentation & Integration (1-2 hours)
1. Create `docs/accessibility-ids.md` reference
2. Update existing Appium tests to use accessibility IDs
3. Run full test suite on physical device + emulator
4. Document any platform-specific quirks

**Total Estimated Time**: 10-16 hours

## Conclusion

This design provides a comprehensive approach to adding Appium accessibility support to Stealth Messenger through Flutter Semantics widgets. The implementation maintains visual consistency while enabling robust automated testing infrastructure. The phased approach allows for incremental development and testing, reducing risk and enabling early feedback.
