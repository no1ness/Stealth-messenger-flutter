# Plan: Telegram-like Web Redesign

**Branch:** feature/telegram-web-redesign
**Created:** 2026-06-20
**Description:** Redesign web version to match Telegram/top messengers layout: left contacts panel + right conversation panel, auto-loaded contacts from shared user directory.

## Settings

- **Testing:** Yes
- **Logging:** Verbose
- **Docs:** Yes — mandatory docs checkpoint

## Analysis

### Current State
- `main_tabs.dart`: Bottom nav with 4 tabs (Chats, Calls, Profile, Settings) — mobile-first
- `chats_screen.dart` (1068 lines): Desktop layout = 3 columns:
  - Left 360px: Chat list + search + stats cards + "New Group" button
  - Center: Conversation panel
  - Right 280px: Insight panel (stats, device info)
- `contacts_screen.dart` (692 lines): Separate screen, contacts loaded from local DB + user directory
- `glass_bottom_nav_bar.dart`: Custom bottom nav (hidden on desktop?)
- `responsive_breakpoints.dart`: mobile <600, tablet <960, desktop ≥961

### Target State (Telegram-like)
- **Left sidebar (≈320px):**
  - Search bar at top
  - Tabs/folders: "Все чаты", "Контакты" (horizontal filter)
  - Chat list with avatars, names, last message preview, timestamps, unread badges
  - NO stats cards, NO "New Group" button in sidebar
  - Contact list auto-loaded from PocketBase `user_profiles` collection
- **Right panel (expanded):**
  - Chat header: avatar + name + online status
  - Message area (existing ConversationPanel)
  - Message input footer (existing ConversationFooter)
- **Remove:** Insight panel (right 280px), stats cards, bottom nav on desktop
- **Mobile:** Keep bottom nav for small screens, but simplify

### Key Constraints
- Contacts auto-load from `UserDirectoryService.fetchAllProfiles()` (PocketBase `user_profiles`)
- Local-first: messages stored locally, contacts discovery via bundle exchange
- Existing E2E encryption and P2P messaging must not break
- `chats_screen.dart` already at 1068 lines — extract new widgets

## Tasks

### Phase 1: Extract & Restructure Layout

- [ ] **Task 1: Create `TelegramSidebar` widget**
  - File: `client/lib/ui/screens/chats/telegram_sidebar.dart`
  - New widget: search bar + tab row + chat/contact list
  - Accept `chats`, `contacts`, `onChatSelected`, `onContactSelected` callbacks
  - Auto-load contacts from `UserDirectoryService().fetchAllProfiles()`
  - Log: `[TelegramSidebar] loaded N contacts, M chats`

- [ ] **Task 2: Create `TelegramHeader` widget**
  - File: `client/lib/ui/screens/chats/telegram_header.dart`
  - Chat header with avatar, name, online status, back button (mobile)
  - Replaces current `GlassAppBar` in conversation view

- [ ] **Task 3: Restructure `ChatsScreen` desktop layout**
  - File: `client/lib/ui/screens/chats_screen.dart`
  - Replace 3-column layout with 2-column: sidebar + conversation
  - Remove insight panel (right 280px)
  - Remove stats cards and "New Group" from desktop view
  - Keep mobile layout as-is (bottom nav + single panel)

### Phase 2: Contact Integration

- [ ] **Task 4: Auto-load contacts in sidebar**
  - File: `client/lib/ui/screens/chats/telegram_sidebar.dart`
  - Call `UserDirectoryService().fetchAllProfiles()` on init
  - Merge with local contacts from `LocalAppService.getContacts()`
  - Show contacts with online status from `PresenceService`
  - Log: `[TelegramSidebar] merged N contacts from directory + local`

- [ ] **Task 5: Add contact-to-chat navigation**
  - Tapping a contact opens/creates a private chat
  - Use existing `LocalAppService.findOrCreatePrivateChatWith()`
  - Log: `[TelegramSidebar] opening chat with contact <userId>`

### Phase 3: Visual Polish

- [ ] **Task 6: Update chat list item design**
  - File: `client/lib/themes/apple_liquid/widgets/chats/chat_tile.dart`
  - Telegram-style: circular avatar, name + last message, timestamp + unread badge
  - Remove stat indicators, keep essential info only
  - Log: N/A (visual change)

- [ ] **Task 7: Remove insight panel and stats cards**
  - File: `client/lib/ui/screens/chats_screen.dart`
  - Delete `_buildInsightPanel()` method
  - Delete `_StatCard` widget class
  - Remove desktop right panel from layout
  - Log: `[ChatsScreen] removed insight panel and stats cards`

### Phase 4: Responsive & Mobile

- [ ] **Task 8: Mobile layout adaptation**
  - File: `client/lib/main_tabs.dart`
  - On mobile: keep bottom nav but simplify tabs (Chats + Settings only?)
  - On desktop: hide bottom nav, show sidebar + conversation
  - Log: `[MainTabs] desktop mode: sidebar layout, mobile: bottom nav`

## Files to Modify

- `client/lib/main_tabs.dart` — desktop/mobile mode switch, hide bottom nav on desktop
- `client/lib/ui/screens/chats_screen.dart` — restructure layout, remove insight/stats
- `client/lib/themes/apple_liquid/widgets/chats/chat_tile.dart` — Telegram-style tile
- `client/lib/helpers/responsive_breakpoints.dart` — may need new breakpoint

## Files to Create

- `client/lib/ui/screens/chats/telegram_sidebar.dart` — new sidebar widget
- `client/lib/ui/screens/chats/telegram_header.dart` — new chat header widget

## Risks

- `chats_screen.dart` is already 1068 lines — extraction is critical to avoid bloat
- Contact auto-load depends on PocketBase `user_profiles` availability
- Bottom nav removal on desktop affects existing navigation flow
- Mobile users expect bottom nav — must preserve for small screens

## Test Coverage

- Widget tests for `TelegramSidebar` (contacts load, search, selection)
- Widget tests for `TelegramHeader` (name, status, back button)
- Golden tests for desktop layout (2-column vs 3-column)
- Integration test: tap contact → opens chat → sends message

## Commit Plan

1. **Tasks 1-3:** `feat(client): extract Telegram sidebar and header, restructure desktop layout`
2. **Tasks 4-5:** `feat(client): auto-load contacts in sidebar with directory merge`
3. **Tasks 6-7:** `style(client): Telegram-style chat tiles, remove insight panel`
4. **Task 8:** `feat(client): responsive desktop/mobile mode switch`
