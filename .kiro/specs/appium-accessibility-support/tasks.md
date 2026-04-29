# Implementation Plan: Appium Accessibility Support

## Overview

Add Flutter `Semantics` widgets to key UI elements across Stealth Messenger so that Appium can locate and interact with them via UiAutomator2 on Android. All changes are purely additive wrappers — no visual or behavioral changes.

## Tasks

- [x] 1. Create AccessibilityIds constants file
  - Create `client/lib/constants/accessibility_ids.dart` with all static label constants and dynamic helpers (`contact(name)`, `chat(name)`)
  - This file is the single source of truth referenced by all subsequent tasks
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 2. Add Semantics to navigation tabs
  - [x] 2.1 Wrap each `_GlassBottomNavBarItemWidget` in `glass_bottom_nav_bar.dart` with `Semantics(label: item.label, button: true)`
    - Use `AccessibilityIds.chatsTab`, `contactsTab`, `profileTab`, `settingsTab` via the item's existing `label` field
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
  - [x] 2.2 Write widget test for navigation tab semantics
    - Pump `GlassBottomNavBar` and assert `find.bySemanticsLabel('Chats')`, `'Contacts'`, `'Profile'` each find one widget
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 3. Add Semantics to contacts screen
  - [x] 3.1 Wrap the contact card `InkWell` in `contacts_screen.dart` with `Semantics(label: AccessibilityIds.contact(name), button: true)`
    - _Requirements: 2.1, 2.2, 2.3_
  - [x] 3.2 Wrap the "Start call" `IconButton` with `Semantics(label: AccessibilityIds.startCall, button: true)`
    - _Requirements: 3.1, 3.2, 3.3, 3.5_
  - [x] 3.3 Wrap the "Start video call" `IconButton` with `Semantics(label: AccessibilityIds.startVideoCall, button: true)`
    - _Requirements: 3.4_
  - [x] 3.4 Wrap the "Add contact" `FilledButton.icon` with `Semantics(label: AccessibilityIds.addContact, button: true)`
    - _Requirements: 2.4_
  - [x] 3.5 Wrap the empty-state `Text('No contacts found')` with `Semantics(label: 'No contacts')`
    - _Requirements: 2.5_
  - [x] 3.6 Wrap inputs and buttons inside `_showAddContactSheet` bottom sheet with Semantics
    - Search `TextField` → `Semantics(label: AccessibilityIds.contactIdInput, textField: true)`
    - "Add" `FilledButton` per result row → `Semantics(label: AccessibilityIds.saveContact, button: true)`
    - _Requirements: 9.1, 9.3, 9.5_
  - [x] 3.7 Write widget tests for contacts screen semantics
    - Assert presence of `'Add contact'`, `'Start call'`, `'Contact Alice'` labels after pumping with mock data
    - _Requirements: 2.1, 2.4, 3.1_

- [x] 4. Add Semantics to call controls (webrtc_call_screen_native_impl.dart)
  - [x] 4.1 Wrap the call status `Text` widget with `Semantics(label: AccessibilityIds.callStatus, liveRegion: true)`
    - The text shows `_formatDuration(...)`, `'Connecting...'`, or `'Calling...'`
    - _Requirements: 5.1, 5.5_
  - [x] 4.2 Wrap the "Hang up" `_buildControlButton` call with `Semantics(label: AccessibilityIds.hangUp, button: true)`
    - _Requirements: 5.2, 5.6_
  - [x] 4.3 Wrap the "Mute" `_buildControlButton` call with `Semantics(label: AccessibilityIds.mute, button: true)`
    - _Requirements: 5.3_
  - [x] 4.4 Wrap the "Speaker" `_buildControlButton` call with `Semantics(label: AccessibilityIds.speaker, button: true)`
    - _Requirements: 5.4_
  - [x] 4.5 Write widget tests for call screen semantics
    - Pump a minimal `WebRTCCallScreen` stub and assert `'Hang up'`, `'Mute'`, `'Speaker'`, `'Call status'` labels exist
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 5. Add Semantics to incoming call dialog (call_manager.dart)
  - [x] 5.1 Wrap the caller name `Text(fromNickname)` with `Semantics(label: AccessibilityIds.callerName)`
    - _Requirements: 4.5_
  - [x] 5.2 Wrap the "Answer" `ElevatedButton.icon` with `Semantics(label: AccessibilityIds.answer, button: true)`
    - _Requirements: 4.1, 4.3_
  - [x] 5.3 Wrap the "Decline" `TextButton.icon` with `Semantics(label: AccessibilityIds.decline, button: true)`
    - _Requirements: 4.2, 4.4_
  - [x] 5.4 Write widget test for incoming call dialog semantics
    - Assert `'Answer'`, `'Decline'`, `'Caller name'` labels are present when dialog is shown
    - _Requirements: 4.1, 4.2, 4.5_

- [x] 6. Checkpoint — ensure all tests pass
  - Run `flutter test` in `client/`; fix any failures before proceeding.

- [x] 7. Add Semantics to chats screen
  - [x] 7.1 Wrap each chat list item widget with `Semantics(label: AccessibilityIds.chat(name), button: true)`
    - Locate the chat list `ListView.builder` item builder in `chats_screen.dart`
    - _Requirements: 7.1, 7.2, 7.3_
  - [x] 7.2 Wrap the empty-state widget with `Semantics(label: 'No chats')`
    - _Requirements: 7.5_
  - [x] 7.3 Wrap the message input field (`GlassMessageInput` or underlying `TextField`) with `Semantics(label: AccessibilityIds.messageInput, textField: true)`
    - _Requirements: 6.1, 6.3_
  - [x] 7.4 Wrap the send button with `Semantics(label: AccessibilityIds.sendMessage, button: true)`
    - _Requirements: 6.2, 6.4_
  - [x] 7.5 Wrap the attachment button with `Semantics(label: AccessibilityIds.attachFile, button: true)`
    - _Requirements: 6.5_
  - [x] 7.6 Write widget tests for chats screen semantics
    - Assert `'Message input'`, `'Send message'`, `'Chat Alice'` labels after pumping with mock data
    - _Requirements: 6.1, 6.2, 7.1_

- [x] 8. Add Semantics to profile screen
  - [x] 8.1 Wrap the User ID `Text(_userId ?? ...)` in `_buildIdentityCard` with `Semantics(label: AccessibilityIds.userId, readOnly: true)`
    - _Requirements: 8.1, 8.2, 8.5_
  - [x] 8.2 Wrap the nickname `TextField` with `Semantics(label: AccessibilityIds.username)`
    - _Requirements: 8.3_
  - [x] 8.3 Wrap the "Copy ID" `FilledButton.icon` with `Semantics(label: AccessibilityIds.copyUserId, button: true)`
    - _Requirements: 8.4_
  - [x] 8.4 Wrap the "Export private key" `OutlinedButton.icon` with `Semantics(label: AccessibilityIds.exportPrivateKey, button: true)`
    - _Requirements: 8.4_
  - [x] 8.5 Wrap the "Logout" `FloatingActionButton.extended` with `Semantics(label: AccessibilityIds.logout, button: true)`
    - _Requirements: 8.4_
  - [x] 8.6 Write widget tests for profile screen semantics
    - Assert `'User ID'`, `'Username'`, `'Copy User ID'` labels are present
    - _Requirements: 8.1, 8.3, 8.4_

- [x] 9. Final checkpoint — ensure all tests pass and wire everything together
  - Run `flutter test` in `client/`; confirm zero failures.
  - Verify `flutter analyze` reports no new issues in modified files.
  - Ensure all `AccessibilityIds` constants are used (no orphaned constants).

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- All Semantics labels use English regardless of UI language (Requirement 10.2)
- `Semantics` wraps existing widgets without altering layout or appearance (Requirement 11.1–11.4)
- `AccessibilityIds` constants file (Task 1) must be created before any other task
