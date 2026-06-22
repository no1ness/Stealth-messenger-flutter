# Plan: Port Telegram-TT Design + Performance Patterns to Flutter

**Branch:** `feature/telegram-tt-design-port`
**Created:** 2026-06-21
**Updated:** 2026-06-21 (refined after deep codebase analysis)
**Description:** Port Telegram Web (telegram-tt) to Flutter — visual design system AND production-proven performance patterns (signal-based state, fasterdom scheduling, lazy loading, virtual scrolling, animation gating). Replace Apple Liquid entirely.

## Settings

- **Testing:** Yes — widget & golden tests for new components
- **Logging:** Verbose — DEBUG-level logs during migration
- **Docs:** Yes — mandatory docs checkpoint at completion
- **Scope:** Full design port + performance patterns. NOT MTProto/backend.

## Analysis

### Source: Telegram-TT
- https://github.com/Ajaxy/telegram-tt — 12+ years of production UI
- Framework: Teact (custom React-like) + SCSS modules
- Three-panel responsive layout: Left → Middle → Right
- Design tokens: CSS custom properties + `themes.json`
- Key performance patterns:
  - **Signal-based state** (`createSignal`) — high-frequency updates without re-renders
  - **Fasterdom** — `requestMeasure`/`requestMutation` for non-thrashing layout
  - **Heavy animation gating** — `beginHeavyAnimation()` pauses non-critical updates
  - **Lazy loading** — `.async.tsx` code-split entry points for every modal/viewer
  - **Virtual scrolling** — infinite scroll with `InfiniteScroll` component
  - **Memoization** — component-level + selector-level
  - **Canvas rendering** — stickers, spoiler effects, animated icons
  - **Scroll preservation** — position restored on tab switch

### Current State (STEALTH — Apple Liquid)
- Dark blue-gray glass surfaces (`#0A0E1A` bg), Apple system palette (`#007AFF`)
- Geist fonts, gradient chat bubbles with scanline overlay
- 2-column desktop layout (TelegramSidebar + ConversationPanel)
- Bottom nav on mobile (GlassBottomNavBar)
- State: raw `setState` + `ValueNotifier` throughout — no signal pattern
- No virtual scrolling — loads messages into memory
- No lazy loading — all screens eagerly imported
- No animation gating — all effects run unconditionally
- **38 non-theme files** import Apple Liquid (~240 import statements)

### What Telegram-TT Design Brings

| Token | Apple Liquid | Telegram Light | Telegram Dark |
|-------|-------------|----------------|---------------|
| Primary | `#007AFF` | `#3390EC` | `#8774E1` |
| Background | `#0A0E1A` | `#FFFFFF` | `#212121` |
| Surface | `#1E2330` (glass) | `#F4F4F5` (flat) | `#0F0F0F` (flat) |
| Own bubble | Gradient blue | `#EEFFDE` | `#766AC8` |
| Text | `#FFFFFF` | `#000000` / `#707579` | `#FFFFFF` / `#AAAAAA` |
| Border | glass sep `#29545458` | `#DADCE0` | `#303030` |
| Font | Geist | Roboto | Roboto |
| Style | Glass + scanlines | Flat, solid | Flat, solid |

### What Exists Already (from previous plan)
- `TelegramSidebar` — search + tabs + list (needs restyling)
- `TelegramHeader` — avatar + name + status (needs restyling)
- 2-column desktop layout in `chats_screen.dart`

### Import Migration Surface (35 files)
| Group | Files | Key Liquid Components |
|-------|-------|---------------------|
| Core screens | `main.dart`, `main_tabs.dart`, `registration_screen.dart`, `loading_screen.dart` | LiquidTheme, StealthLoadingIndicator, GlassBottomNavBar, StealthBackground, GlassTextField, GrainOverlay, StealthHaptics, CircuitBoardBackground, DecryptText |
| Chat screens | `chats_screen.dart`, `conversation_panel.dart`, `conversation_footer.dart`, `telegram_sidebar.dart`, `telegram_header.dart`, `chat_search_bar.dart`, `insight_panel.dart`, `chat_list_panel.dart`, `group_management_sheet.dart`, `conversation_attachment.dart` | AppColors, AppSpacing, AppTypography, GlassChatBubble, GlassMessageInput, GlassTextField, ChatTile, GlassAppBar, SectionHeader, StealthSkeleton, StealthSnackBar |
| Call screens | `webrtc_call_screen_web.dart`, `webrtc_call_screen_native_impl.dart`, `webrtc_call_screen_stub.dart` | CallHudOverlay, StatusChip, StealthBackground, StealthSnackBar, GlassAppBar, GlassContainer |
| Diagnostics | `webrtc_diagnostics_screen_web.dart`, `webrtc_diagnostics_screen_native_impl.dart`, `webrtc_diagnostics_screen_stub.dart`, `diagnostics_screen.dart`, `level_filter_chips.dart`, `log_entry_tile.dart`, `service_status_tile.dart`, `performance_monitor.dart` | GlassAppBar, GlassContainer, SectionHeader, StealthBackground, StealthSnackBar |
| Misc screens | `contacts_screen.dart`, `profile_screen.dart`, `calls_screen.dart`, `settings_screen.dart`, `monitoring_screen.dart`, `startup_error_screen.dart`, `app_update/update_prompt_screen.dart`, `app_update/update_status_card.dart`, `dashboard/dashboard_home_screen.dart` | GlassPageRoute, ContactTile, GlassTextField, GlassContainer, StealthDialog, StealthLoadingIndicator, GlassAppBar, SectionHeader, StealthHaptics, StealthSnackBar |
| Shared widgets | `chat_bubble.dart`, `call_manager.dart`, `empty_state.dart`, `voice_message_player.dart`, `message_input.dart`, `user_detail_sheet.dart` | StealthDialog, StealthSnackBar, StealthLoadingIndicator, GlassPageRoute, GrainOverlay, AppColors, StealthHaptics |

### What Telegram-TT Performance Patterns Map To

| Telegram-TT Pattern | Flutter Equivalent | Why It Matters |
|--------------------|-------------------|----------------|
| `createSignal` | `ValueNotifier<T>` per field | Avoids full-widget rebuild on every keystroke/typing indicator |
| `fasterdom` | `WidgetsBinding.instance.addPostFrameCallback` + `RenderObject` scheduling | Prevents layout thrashing during animation frames |
| `beginHeavyAnimation()` | `AnimationGate` — `ValueNotifier<bool>` that pauses non-critical streams | Keeps UI responsive during message send/receive bursts |
| `.async.tsx` code-split | `DeferredWidget` — `deferred as` + `FutureBuilder` | Lazy-load modals, media viewer, story viewer |
| `InfiniteScroll` | `ScrollController` + threshold-based append | Memory-safe message list for 10k+ messages |
| `memo` / selectors | `const` widgets + `shouldRebuild` / `Equatable` | Skip unnecessary rebuilds in chat list |
| Canvas stickers | `flutter_lottie` + `CustomPainter` | Smooth sticker animation without jank |
| Scroll preservation | `PageStorage` + `ScrollPosition` restore | Chat position survives tab switch |

## Key Design Decisions

1. **Apple Liquid полностью удаляется** — Telegram-TT становится единственной темой.
2. **Telegram-TT theme** — `client/lib/themes/telegram_tt/` единственный провайдер темы.
3. **`theme_controller.dart`** (at `themes/` root) — generic, не удаляется, адаптируется под TgTheme.
4. **Barrel export** — `telegram_tt.dart` как единая точка входа для всех импортов.
5. **No glass, no scanline, no grain, no chromatic aberration** — Telegram flat design.
6. **Signal-like state** — `ValueNotifier` per-field для typing, presence, unread counts.
7. **Animation gate** — `AnimationGate` для паузы не-критичных анимаций.
8. **Lazy loading** — `DeferredWidget` для MediaViewer, StoryViewer, модалок.
9. **Virtual scroll** — `TgMessageList` через `ScrollController` + порог подгрузки.
10. **Chat wallpaper** — Telegram-style background + pattern.
11. **Roboto + Roboto Mono** вместо Geist.
12. **Все компоненты с префиксом `Tg`**.

## Critical Implementation Order

```
Phase 0: Create telegram_tt theme + barrel export (app still uses Liquid)
Phase 1: Create Telegram-style widgets (bubbles, tiles, headers, etc.)
Phase 2: Performance patterns (Signal, AnimationGate, DeferredWidget, etc.)
Phase 3: Responsive layout + right panel
Phase 4: Chat background + wallpaper
Phase 5: Animations, transitions, polish
Phase 6: Migrate all 38 files → switch theme → delete apple_liquid
```

**CRITICAL:** Apple Liquid файлы удаляются ТОЛЬКО в конце Phase 6, когда все 38 файлов уже переведены на telegram_tt импорты.

## Tasks

### Phase 0: Create Telegram Design Tokens + Theme Bundle

- [x] **Task 0.1: Create `telegram_tt/` theme directory structure**
  - Create: `client/lib/themes/telegram_tt/` with subdirs:
    - `constants/` (colors, typography, spacing, motion)
    - `widgets/` (bubbles, tiles, inputs, headers, avatars, nav)
    - `feedback/` (loading, dialogs, snackbars, haptics)
    - `effects/` (ripple, animation gate, transitions)
    - `navigation/` (page route)
    - `utils/` (signal, schedule, deferred)
  - Log: `[Theme] created telegram_tt package`

- [x] **Task 0.2: Create `TgColors` — Telegram-TT color tokens**
  - File: `client/lib/themes/telegram_tt/constants/tg_colors.dart`
  - Light: primary `#3390EC`, bg `#FFFFFF`, surface `#F4F4F5`, ownBubble `#EEFFDE`, text `#000000`, textSecondary `#707579`, border `#DADCE0`, bordersInput `#DADCE0`, dividers `#C8C6CC`, error `#E53935`, success `#00C73E`, link `#3390EC`, chatHover `#F4F4F5`, chatActive `#3390EC`, messageReaction `#EBF3FD`, scrollbar `rgba(90,90,90,0.3)`, shadow `#72727240`
  - Dark: primary `#8774E1`, bg `#212121`, surface `#0F0F0F`, ownBubble `#766AC8`, text `#FFFFFF`, textSecondary `#AAAAAA`, border `#303030`, dividers `#3B3B3D`, chatHover `#2C2C2C`, chatActive `#766AC8`, messageReaction `#2B2A35`, scrollbar `rgba(90,90,90,0.3)`, shadow `#1010109C`
  - Static helpers: `TgColors.of(context).primary`
  - Log: `[TgColors] defined N tokens`

- [x] **Task 0.3: Create `TgTypography` — Telegram typography**
  - File: `client/lib/themes/telegram_tt/constants/tg_typography.dart`
  - Font: `Roboto` (400, 500, 700), `RobotoMono` (400, 500)
  - Styles: `chatName` 16px/500, `chatSubtitle` 14px/400, `headerTitle` 20px/500 (left) / 18px/500 (middle), `messageText` 16px/400, `statusText` 14px/400, `badge` 12px/500, `timestamp` 11px/400, `stickyDate` 14px/500
  - `TgTypography.textTheme(brightness)` → `TextTheme`
  - Log: `[TgTypography] defined N text styles`

- [x] **Task 0.4: Create `TgSpacing` — Telegram spacing & layout**
  - File: `client/lib/themes/telegram_tt/constants/tg_spacing.dart`
  - Scale: `xs` 4, `sm` 8, `md` 16, `lg` 24, `xl` 32, `xxl` 48
  - Dimens: `headerHeight` 56, `chatListItemHeight` 48, `inputHeight` 48, `bubbleRadius` 15, `bubbleRadiusSmall` 6, `buttonRadius` 16, `modalRadius` 32, `sidebarWidth` 320, `iconSize` 22, `rightColumnWidthDesktop` `0.25` (25vw), `rightColumnWidthLarge` `424`
  - `EdgeInsets` helpers
  - Log: `[TgSpacing] defined spacing scale + N dimens`

- [x] **Task 0.5: Create `TgMotion` — Telegram animation profiles**
  - File: `client/lib/themes/telegram_tt/constants/tg_motion.dart`
  - Desktop: `layerDuration` 300ms, `slideDuration` 300ms, `messageMount` 200ms easeOut, `selectDuration` 200ms easeOut
  - Curves: `layerCurve` `cubicBezier(0.33,1,0.68,1)`, `slideCurve` `cubicBezier(0.25,1,0.5,1)`
  - iOS: `layerDuration` 650ms, `slideDuration` 450ms
  - Animation builders: `messageMountAnimation(controller)`
  - Log: `[TgMotion] defined N profiles`

- [x] **Task 0.6: Create `TgThemeData` — full Flutter ThemeData**
  - File: `client/lib/themes/telegram_tt/tg_theme.dart`
  - `static ThemeData get lightTheme` and `get darkTheme`
  - Wire all Material slots: `AppBarTheme`, `CardTheme`, `DialogTheme`, `InputDecorationTheme`, `TextTheme`, `ButtonThemeData`, `BottomNavigationBarTheme`, `DividerTheme`, `ChipTheme`, `IconTheme`, `SnackBarTheme`, `TooltipTheme`, `PopupMenuTheme`, `ProgressIndicatorTheme`, `FloatingActionButtonTheme`, `PageTransitionsTheme`, `TextSelectionTheme`
  - `static ThemeData of(BuildContext)` — convenience getter
  - Log: `[TgTheme] built light + dark ThemeData`

- [x] **Task 0.7: Create barrel export `telegram_tt.dart`**
  - File: `client/lib/themes/telegram_tt/telegram_tt.dart`
  - Re-export all constants, widgets, feedback, effects, navigation, utils
  - Single import: `import 'package:stealth/themes/telegram_tt/telegram_tt.dart'`
  - Replaces ~240 individual `apple_liquid/` import lines
  - Log: `[Barrel] telegram_tt.dart exports N modules`

### Phase 1: Core UI Components

- [x] **Task 1.1: Create `TgChatBubble` — flat Telegram-style bubble**
  - File: `client/lib/themes/telegram_tt/widgets/tg_chat_bubble.dart`
  - Flat bg: own = `TgColors.ownBubble`, received = `TgColors.background`
  - Corner radius: single 15px, middle left-small 6px, last top-left-small 6px, tail 0
  - Max width: 464px incoming / 480px outgoing
  - Margin bottom: 6px (4px mobile)
  - Delivery ticks (single → double → blue double check)
  - Reply preview: left accent bar + name + snippet
  - Message mount animation: translateY(32px) + opacity 200ms easeOut
  - Const constructor for rebuild optimization
  - Log: `[TgChatBubble] type=<sent|received> group=<position>`

- [x] **Task 1.2: Create `TgChatTile` — Telegram chat list item**
  - File: `client/lib/themes/telegram_tt/widgets/tg_chat_tile.dart`
  - 48px min-height, 16px horizontal padding
  - Avatar (40px) + name (16px/500) + subtitle (14px/400)
  - Timestamp, unread badge (12px/500 primary fill)
  - Hover `TgColors.chatHover`, active `TgColors.chatActive`
  - Selected: left bar 3px primary
  - Typing indicator: green "Печатает..."
  - Const + `==` override
  - Log: `[TgChatTile] chat=<name> unread=<n>`

- [x] **Task 1.3: Create `TgHeader` — Telegram conversation header**
  - File: `client/lib/themes/telegram_tt/widgets/tg_header.dart`
  - 56px, solid `TgColors.background`, bottom border
  - Avatar (40px) + name (18px/500) + status (14px, online=primary)
  - Right: search + menu icons
  - Menu dropdown: View Profile, Search, Clear History, Delete
  - Sticky pinned at top during scroll
  - Log: `[TgHeader] chat=<name> online=<bool>`

- [x] **Task 1.4: Create `TgMessageInput` — Telegram composer**
  - File: `client/lib/themes/telegram_tt/widgets/tg_message_input.dart`
  - Container 48px, flat bg, border-top
  - Input: rounded 16px, solid bg, border `TgColors.bordersInput`
  - Focus: border primary + inset shadow
  - Attachment (paperclip), send button (primary circle with arrow / mic)
  - Reply preview bar above input
  - Multiline (max 6 lines)
  - Log: `[TgMessageInput] text=<len> reply=<id>`

- [x] **Task 1.5: Create `TgAvatar` — Telegram avatar**
  - File: `client/lib/themes/telegram_tt/widgets/tg_avatar.dart`
  - Circular clip, default 40px (24-56 range)
  - Initials (2 chars) from name
  - Gradient from name hash (8 preset Telegram gradients)
  - Online dot: 6px green, bottom-right
  - Group: "G" or multi-stack
  - Const constructor
  - Log: `[TgAvatar] name=<name> online=<bool>`

- [x] **Task 1.6: Create `TgSearchField` — Telegram search**
  - File: `client/lib/themes/telegram_tt/widgets/tg_search_field.dart`
  - Rounded 16px, height 36px, search icon left, clear X right
  - Solid bg (light: #F4F4F5, dark: #0F0F0F)
  - Debounce 300ms
  - Log: `[TgSearchField] query=<text>`

- [x] **Task 1.7: Create `TgFeedback` components — loading, dialog, snackbar, haptics, skeleton**
  - Files:
    - `client/lib/themes/telegram_tt/feedback/tg_loading_indicator.dart` — Telegram-style spinner
    - `client/lib/themes/telegram_tt/feedback/tg_dialog.dart` — flat dialog with Telegram radii (32px)
    - `client/lib/themes/telegram_tt/feedback/tg_snack_bar.dart` — flat toast (radius 16px)
    - `client/lib/themes/telegram_tt/feedback/tg_haptics.dart` — haptic bridge (web stub)
    - `client/lib/themes/telegram_tt/feedback/tg_skeleton.dart` — `TgSkeletonTile` + `TgSkeletonList`, flat gray placeholders
  - Replace `StealthLoadingIndicator`, `StealthDialog`, `StealthSnackBar`, `StealthHaptics`, `StealthSkeletonTile/List`
  - Log: `[TgFeedback] created loading, dialog, snackbar, haptics, skeleton`

- [x] **Task 1.8: Create `TgCallHudOverlay` — Telegram-style call HUD**
  - File: `client/lib/themes/telegram_tt/widgets/call/tg_call_hud_overlay.dart`
  - Replaces `CallHudOverlay` from apple_liquid
  - Flat design, Telegram colors, uses `TgStatusChip`
  - Log: `[TgCallHud] created`

- [x] **Task 1.9: Create `TgStatusChip` — Telegram status indicator**
  - File: `client/lib/themes/telegram_tt/widgets/tg_status_chip.dart`
  - Replaces `StatusChip` from apple_liquid
  - Flat chip with icon + text, colors: online=green, offline=gray, calling=primary
  - Border radius 6px, 14px/400 text
  - Log: `[TgStatusChip] type=<online|offline|calling>`

- [x] **Task 1.10: Create `TgSectionHeader` — Telegram section label**
  - File: `client/lib/themes/telegram_tt/widgets/tg_section_header.dart`
  - Replaces `SectionHeader` from apple_liquid
  - Flat 14px/400 `TgColors.textSecondary` label with optional count badge
  - Padding 16px horizontal, 8px vertical
  - Log: `[TgSectionHeader] label=<text> count=<n>`

- [x] **Task 1.11: Create `TgListDivider` — Telegram list hairline**
  - File: `client/lib/themes/telegram_tt/widgets/tg_list_divider.dart`
  - Replaces `ListDivider` from apple_liquid
  - 0.5px hairline in `TgColors.dividers`
  - Log: `[TgListDivider] rendered`

- [x] **Task 1.12: Create `TgDeliveryStatus` — Telegram delivery tick**
  - File: `client/lib/themes/telegram_tt/widgets/tg_delivery_status.dart`
  - Replaces `OutgoingDeliveryStatusIcon` from apple_liquid
  - States: clock (pending) → single check (sent) → double check (delivered) → blue double check (read)
  - Telegram green `#4FAE4E` for delivered/read
  - Used standalone and inside `TgChatBubble`
  - Log: `[TgDeliveryStatus] state=<pending|sent|delivered|read>`

- [x] **Task 1.13: Create `TgCard` — Telegram-style flat card**
  - File: `client/lib/themes/telegram_tt/widgets/tg_card.dart`
  - Replaces `GlassContainer`/`GlassCard`/`GlassButton` from apple_liquid
  - Flat bg: `TgColors.surface`, radius 16px, no border, no shadow
  - Optional: `TgColors.border` border variant for list cards
  - `TgCard`, `TgCardSection`, `TgCardTile` variants
  - Log: `[TgCard] created`

- [x] **Task 1.14: Create `TgNavBar` — Telegram navigation (desktop rail + mobile tabs)**
  - File: `client/lib/themes/telegram_tt/widgets/tg_nav_bar.dart`
  - Desktop: 68px vertical nav rail with icon + label (chats, calls, profile, settings)
  - Mobile: wraps `TgTabBar` from Task 3.5 (compact bottom tabs, icon-only)
  - Selected state: icon tinted `TgColors.primary`, label `TgColors.primary`
  - Unselected: `TgColors.textSecondary`
  - Replaces `GlassBottomNavBar`
  - Log: `[TgNavBar] nav=<desktop|mobile> selected=<index>`

### Phase 2: Performance Patterns

- [x] **Task 2.1: Create `ValueSignal<T>` — Telegram-inspired signal pattern**
  - File: `client/lib/themes/telegram_tt/utils/value_signal.dart`
  - Wraps `ValueNotifier<T>` with `.peek()`, `.onChange` stream, auto-dispose
  - Log: `[Signal] created ValueSignal<T>`

- [x] **Task 2.2: Create `AnimationGate` — heavy animation throttle**
  - File: `client/lib/themes/telegram_tt/effects/animation_gate.dart`
  - `ValueNotifier<bool>` that gates non-critical animations
  - `beginHeavy()` / `endHeavy()` — pause/resume
  - Log: `[AnimationGate] gate=<open|closed>`

- [x] **Task 2.3: Create `DeferredWidget` — lazy loading pattern**
  - File: `client/lib/themes/telegram_tt/widgets/deferred_widget.dart`
  - `DeferredWidget(loader: () => import('...'))` with loading placeholder
  - For: MediaViewer, StoryViewer, ContactPicker, GroupCreateSheet, EmojiPicker
  - Log: `[DeferredWidget] loaded <module> in <ms>ms`

- [x] **Task 2.4: Create `TgMessageList` — virtual scrolling message list**
  - File: `client/lib/themes/telegram_tt/widgets/tg_message_list.dart`
  - `ScrollController` with threshold-based append (200px from top)
  - `VisibilityDetector` — only build visible + 3 screenfuls buffer
  - Preserve scroll via `PageStorage`
  - Log: `[TgMessageList] rendered <n> messages`

- [x] **Task 2.5: Create `TgInfiniteScroll` — reusable lazy list**
  - File: `client/lib/themes/telegram_tt/widgets/tg_infinite_scroll.dart`
  - Wraps `ListView.builder` with `onLoadMore`, `hasMore`, loading indicator
  - Log: `[TgInfiniteScroll] loaded page <n>`

- [x] **Task 2.6: Create `schedule` helpers — fasterdom pattern**
  - File: `client/lib/themes/telegram_tt/utils/schedule.dart`
  - `scheduleMeasure(cb)` — `addPostFrameCallback` + dedup
  - `scheduleMutation(cb)` — next microtask
  - Log: `[Schedule] measure/mutation queued`

### Phase 3: Responsive Layout & Right Panel

- [ ] **Task 3.1: Update breakpoints to Telegram-TT spec**
  - File: `client/lib/helpers/responsive_breakpoints.dart`
  - Breakpoints: mobile <600, tablet 600-1275, desktop 1276-1920, large >1921, xlarge >2600
  - `rightColumnWidth(width)` — 0 / 25vw / 424px
  - `messagesContainerWidth(width)` — responsive
  - Log: `[Breakpoints] device=<t>`

- [ ] **Task 3.2: Add right column panel**
  - File: `client/lib/ui/screens/chats/conversation_panel.dart`
  - Desktop+: right column (chat info, shared media, members)
  - Slide: `AnimatedContainer` 0↔rightColumnWidth, `TgMotion.layerDuration`
  - Toggle from TgHeader menu
  - Log: `[Layout] rightColumn=<open|closed>`

- [ ] **Task 3.3: Refine sidebar with Telegram styles**
  - File: `client/lib/ui/screens/chats/telegram_sidebar.dart`
  - Replace AppColors/AppSpacing/AppTypography → TgColors/TgSpacing/TgTypography
  - Search → `TgSearchField`, chat list → `TgChatTile`, tabs → `TgTabBar`
  - Width: 320px fixed desktop, full mobile
  - Log: `[TgSidebar] restyled`

- [ ] **Task 3.4: Update main navigation**
  - File: `client/lib/main_tabs.dart`
  - Desktop: 68px nav rail (chats, calls, profile, settings) + content
  - Mobile: bottom nav with `TgNavBar`
  - Remove `GlassBottomNavBar`, `StealthAnimatedBackground`, `DebugStatusBar`
  - Replace with Telegram flat equivalents
  - Log: `[MainTabs] nav=<desktop|mobile>`

- [x] **Task 3.5: Create `TgTabBar` + `TgTab` — flat tab components**
  - File: `client/lib/themes/telegram_tt/widgets/tg_tab_bar.dart`
  - No bottom indicator, selected bold primary, unselected textSecondary
  - Log: `[TgTabBar] selected=<i>`

### Phase 4: Chat Background & Wallpaper

- [x] **Task 4.1: Create `TgChatBackground` — wallpaper/pattern system**
  - File: `client/lib/themes/telegram_tt/widgets/tg_chat_background.dart`
  - Default: white (#FFFFFF) light, #212121 dark
  - Pattern SVG overlay
  - Custom wallpaper + blur(12)
  - Scale: 73% when right column open (desktop 1276-1920)
  - Log: `[TgChatBackground] type=<default|pattern|custom>`

- [ ] **Task 4.2: Integrate wallpaper into conversation panel**
  - File: `client/lib/ui/screens/chats/conversation_panel.dart`
  - `TgChatBackground` as base stack layer
  - Log: `[ConversationPanel] background=<type>`

### Phase 5: Polish — Animations, Transitions, Buttons

- [x] **Task 5.1: Create `TgPageTransition` — Telegram page transitions**
  - File: `client/lib/themes/telegram_tt/navigation/tg_page_transition.dart`
  - Replaces `GlassPageRoute`
  - Desktop 300ms slide, Android 350ms, iOS 450ms
  - Log: `[TgPageTransition] route type`

- [x] **Task 5.2: Create `TgRipple` — Telegram touch feedback**
  - File: `client/lib/themes/telegram_tt/effects/tg_ripple.dart`
  - Color: `TgColors.primary` 10% opacity, 150ms
  - Wraps `InkWell`
  - Log: N/A

- [x] **Task 5.3: Create `TgButton` — Telegram button styles**
  - File: `client/lib/themes/telegram_tt/widgets/tg_button.dart`
  - Primary, secondary, text, icon variants
  - Radius 16px, height 44px
  - Log: `[TgButton] type=<variant>`

- [x] **Task 5.4: Create `TgStickyDate` — date separators**
  - File: `client/lib/themes/telegram_tt/widgets/tg_sticky_date.dart`
  - 14px/500 centered, floating, slight opacity bg
  - z-index 9
  - Log: `[TgStickyDate] date=<label>`

- [x] **Task 5.5: Create `TgUnreadSeparator` — unread count bar**
  - File: `client/lib/themes/telegram_tt/widgets/tg_unread_separator.dart`
  - "N unread messages", primary bg, white text
  - Log: `[TgUnreadSep] count=<n>`

### Phase 6: Import Migration, Theme Switch & Cleanup

**Sub-phase 6A: Migrate core screens (5 tasks)**

- [x] **Task 6.1: Migrate `main.dart` to telegram_tt**
  - Add: `import 'package:stealth/themes/telegram_tt/telegram_tt.dart'` (for `TgTheme`, `TgLoadingIndicator`)
  - Replace: `StealthLoadingIndicator` → `TgLoadingIndicator` (now from barrel)
  - **KEEP** `liquid_theme.dart` import — `LiquidTheme.theme` still referenced until Task 6.15
  - Adapt `ThemeController` to use `TgTheme.theme` / `TgTheme.darkTheme` (NOT create new controller)
  - Log: `[Migrate] main.dart → telegram_tt (dual imports: liquid_theme kept until 6.15)`

- [x] **Task 6.2: Migrate `main_tabs.dart` to telegram_tt**
  - Replace: `AppColors/AppSpacing/AppTypography` → `TgColors/TgSpacing/TgTypography`
  - Replace: `GlassBottomNavBar` → `TgNavBar`
  - Replace: `StealthAnimatedBackground` → solid `TgColors.background`
  - Replace: `DebugStatusBar` → simplified dev-only indicator
  - Log: `[Migrate] main_tabs.dart → telegram_tt`

- [x] **Task 6.3: Migrate `registration_screen.dart` (at `client/lib/registration_screen.dart`)**
  - Replace: 9 Liquid imports (GrainOverlay, StealthHaptics, StealthLoadingIndicator, StealthSnackBar, StealthBackground, GlassTextField, AppColors, AppSpacing, AppTypography)
  → Telegram equivalents
  - Log: `[Migrate] registration_screen.dart → telegram_tt`

- [x] **Task 6.4: Migrate `loading_screen.dart` — Telegram-style loading**
  - Replace complex animation (GlassContainer, CircuitBoardBackground, StealthBackground, DecryptText, liquid gradients) with clean Telegram-style loading:
    - Solid `TgColors.background` (no animated gradient, no circuit board)
    - Centered STEALTH logo text + `TgLoadingIndicator`
    - No decrypt/scan animations — Telegram keeps loading minimal
  - Replace: `AppColors/Motion/Spacing/Typography` → `TgColors/TgSpacing/TgTypography`
  - Log: `[Migrate] loading_screen.dart → telegram_tt (simplified to centered logo + spinner)`

- [x] **Task 6.5: Migrate `startup_error_screen.dart`**
  - Replace: `StealthBackground`, `AppColors/Spacing/Typography` → Telegram equivalents
  - Log: `[Migrate] startup_error_screen.dart → telegram_tt`

**Sub-phase 6B: Migrate chat screens (7 files)**

- [x] **Task 6.6: Migrate `chats_screen.dart` (at `client/lib/ui/screens/chats_screen.dart`; ~992 lines)**
  - Replace: `ChatTile` → `TgChatTile`, `GlassAppBar` → `TgHeader`, `StealthSkeleton` → `TgSkeleton`, `StealthSnackBar` → `TgSnackBar`, `SectionHeader` → `TgSectionHeader`, `AppColors/Spacing/Typography` → `TgColors/TgSpacing/TgTypography`
  - Log: `[Migrate] chats_screen.dart → telegram_tt`

- [x] **Task 6.7: Migrate `conversation_panel.dart`**
  - Replace: `GlassChatBubble` → `TgChatBubble`, `StealthLoadingIndicator`, `OutgoingDeliveryStatusIcon`, `AppColors`
  - Integrate `TgChatBackground` as stack layer
  - Log: `[Migrate] conversation_panel.dart → telegram_tt`

- [x] **Task 6.8: Migrate `conversation_footer.dart`**
  - Replace: `GlassMessageInput` → `TgMessageInput`, `AppColors`
  - Log: `[Migrate] conversation_footer.dart → telegram_tt`

- [x] **Task 6.9: Migrate `telegram_sidebar.dart` & `telegram_header.dart`**
  - Replace: `AppColors/Spacing/Typography` → `TgColors/TgSpacing/TgTypography`
  - Replace: `GlassTextField` → `TgSearchField`, `ChatTile` → `TgChatTile`
  - Log: `[Migrate] telegram_sidebar/header → telegram_tt`

- [x] **Task 6.10: Migrate chat sub-widgets (all under `client/lib/ui/screens/chats/`)**
  - Files: `chat_search_bar.dart`, `insight_panel.dart`, `chat_list_panel.dart`, `conversation_attachment.dart`, `group_management_sheet.dart`
  - Replace Liquid imports → Telegram equivalents
  - Log: `[Migrate] chat sub-widgets → telegram_tt`

**Sub-phase 6C: Migrate call + diagnostics screens (11 files)**

- [ ] **Task 6.11: Migrate call screens (web, native_impl, stub)**
  - Files: `webrtc_call_screen_web.dart`, `webrtc_call_screen_native_impl.dart`, `webrtc_call_screen_stub.dart`
  - Replace: `CallHudOverlay` → `TgCallHudOverlay`, `StatusChip`, `StealthBackground`, `StealthSnackBar`, `GlassAppBar`, `GlassContainer`, `AppColors/Spacing/Typography`
  - Log: `[Migrate] call screens → telegram_tt`

- [ ] **Task 6.12: Migrate diagnostics screens (web, native_impl, stub, plus 4 widgets)**
  - Files: `webrtc_diagnostics_screen_web.dart`, `webrtc_diagnostics_screen_native_impl.dart`, `webrtc_diagnostics_screen_stub.dart`, `diagnostics_screen.dart`, `level_filter_chips.dart`, `log_entry_tile.dart`, `service_status_tile.dart`, `performance_monitor.dart`
  - Replace: `GlassAppBar` → `TgHeader`, `GlassContainer`, `SectionHeader`, `StealthBackground`, `StealthSnackBar`, `AppColors/Spacing/Typography`
  - Log: `[Migrate] diagnostics → telegram_tt`

**Sub-phase 6D: Migrate remaining screens + shared widgets (9 files)**

- [ ] **Task 6.13: Migrate remaining screens**
  - Files: `client/lib/ui/screens/contacts_screen.dart`, `client/lib/ui/screens/profile_screen.dart`, `client/lib/ui/screens/calls_screen.dart`, `client/lib/ui/screens/settings_screen.dart`, `client/lib/ui/screens/monitoring_screen.dart`, `client/lib/ui/screens/app_update/update_prompt_screen.dart`, `client/lib/ui/screens/app_update/update_status_card.dart`, `client/lib/ui/screens/dashboard/dashboard_home_screen.dart`
  - Replace per-file Liquid imports → Telegram equivalents
  - Log: `[Migrate] remaining screens (N files) → telegram_tt`

- [ ] **Task 6.14: Migrate shared widgets**
  - Files: `client/lib/ui/widgets/chat_bubble.dart`, `client/lib/ui/widgets/call_manager.dart`, `client/lib/ui/widgets/empty_state.dart`, `client/lib/ui/widgets/voice_message_player.dart`, `client/lib/ui/widgets/message_input.dart`, `client/lib/ui/sheets/user_detail_sheet.dart`
  - Replace: `StealthDialog` → `TgDialog`, `StealthSnackBar` → `TgSnackBar`, `StealthLoadingIndicator` → `TgLoadingIndicator`, `GlassPageRoute` → `TgPageTransition`, `AppColors` → `TgColors`, `StealthHaptics` → `TgHaptics`
  - **`empty_state.dart`**: remove `GrainOverlay` + hex-fingerprint pattern bg. Redesign as clean Telegram-style centered icon + text on `TgColors.background` (no grain, no effects, no circuit board)
  - Log: `[Migrate] shared widgets (N files) → telegram_tt`

**Sub-phase 6E: Theme switch + final cleanup**

- [ ] **Task 6.15: Switch app to Telegram theme**
  - File: `client/lib/main.dart`
  - Change: `theme: LiquidTheme.theme` → `theme: TgTheme.lightTheme`
  - Change: `darkTheme: LiquidTheme.darkTheme` → `darkTheme: TgTheme.darkTheme`
  - `ThemeController.loadInitial()` stays as-is (it's generic)
  - Verify app builds and renders with Telegram theme
  - Log: `[ThemeSwitch] app now uses telegram_tt theme`

- [ ] **Task 6.16: Add fonts — Roboto + Roboto Mono**
  - File: `client/pubspec.yaml`
  - Add Roboto (400, 500, 700) and Roboto Mono (400, 500)
  - Download → `assets/fonts/`
  - Remove Geist + GeistMono font entries
  - Log: `[Fonts] Roboto registered, Geist removed`

- [ ] **Task 6.17: Delete `apple_liquid/` directory + tests**
  - Remove entire `client/lib/themes/apple_liquid/` tree (~43 files)
  - Remove `client/test/themes/apple_liquid/` tree (13 test files)
  - Log: `[Cleanup] deleted apple_liquid (43 files + 13 tests)`

- [ ] **Task 6.18: Widget tests for new Telegram components**
  - `TgChatBubble`: 4 positions × 2 types + reply + attachment → 12 tests
  - `TgChatTile`: selected/unselected/hover/unread/typing → 8 tests
  - `TgHeader`: with/without back + online/offline + menu → 6 tests
  - `TgMessageInput`: empty/text/attachment/reply → 4 tests
  - `TgAvatar`: initials/gradient/online → 4 tests
  - `TgSearchField`: empty/text/debounce → 3 tests
  - `TgPageTransition`: route transition test → 2 tests
  - Golden: sidebar, conversation panel, desktop layout, dark theme → 4 tests
  - Log: `[Tests] added N widget tests`

- [ ] **Task 6.19: Update E2E tests**
  - Run `node run.mjs suite` — fix selectors for Telegram-TT classes/ids
  - Update any DOM queries that relied on Apple Liquid class names
  - Verify call + chat scenarios pass
  - Log: `[E2E] suite <pass|fail>`

## Commit Plan

1. **Phase 0 — Tokens:** `feat(client): add Telegram-TT design tokens and barrel export — colors, typography, spacing, motion, ThemeData`
2. **Phase 1 — Components:** `feat(client): add Telegram-style core components — bubbles, tiles, headers, input, avatar, search, status chip, section header, divider, delivery status, card, skeleton, nav bar, feedback, call HUD`
3. **Phase 2 — Performance:** `feat(client): add Telegram-TT performance patterns — ValueSignal, AnimationGate, DeferredWidget, virtual scrolling, fasterdom`
4. **Phase 3 — Layout:** `feat(client): implement Telegram responsive layout with 4 breakpoints, right panel, nav bars, tabs`
5. **Phase 4 — Background:** `feat(client): add chat background and wallpaper system`
6. **Phase 5 — Polish:** `feat(client): add Telegram-style animations, transitions, buttons, sticky dates`
7. **Phase 6A — Core screens:** `migrate(client): switch main.dart, main_tabs, registration, loading, startup screens to telegram_tt`
8. **Phase 6B — Chat screens:** `migrate(client): switch chat screens and sub-widgets to telegram_tt`
9. **Phase 6C — Call/Diagnostics:** `migrate(client): switch call and diagnostics screens to telegram_tt`
10. **Phase 6D — Remaining:** `migrate(client): switch remaining screens and shared widgets to telegram_tt`
11. **Phase 6E — Finalize:** `feat(client): switch to telegram_tt theme, add Roboto fonts, remove Apple Liquid, add tests`

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Plan has 50+ tasks | Refined import migration into 14 explicit file-group tasks (6.1-6.14) + 6 added replacement components (1.9-1.13) |
| Build breaks during intermediate phases | Telegram theme is created first; app continues using Liquid until Phase 6.15 switch |
| 38 non-theme files with ~760 Liquid import/usage lines need updating | Barrel export (`telegram_tt.dart`) minimizes per-file changes to single import line |
| Apple Liquid deletion too early | Moved to very end (Task 6.17) — only after all 38 files are migrated |
| Call HUD + GlassPageRoute have no planned replacement | Added Tasks 1.8 (TgCallHudOverlay) and 5.1 (TgPageTransition) |
| `theme_controller.dart` misunderstood | Now documented as generic — adapted, not recreated |
| Test sync — stub implementations vs tests | Patch pattern applied: update tests in same commit as widget changes |
| E2E selectors break | Task 6.19 runs full suite after migration; fixes selectors before commit |
| `chats_screen.dart` already 992 lines | Extract panel logic during Phase 3 refactoring |

## Test Coverage

- `TgChatBubble`: 4 positions × 2 types + reply + attachment → 12 widget tests
- `TgChatTile`: selected/unselected/hover/unread/typing → 8 widget tests
- `TgHeader`: with/without back + online/offline + menu → 6 widget tests
- `TgMessageInput`: empty/text/attachment/reply → 4 widget tests
- `TgAvatar`: initials/gradient/online → 4 widget tests
- `TgSearchField`: empty/text/debounce → 3 widget tests
- `TgPageTransition`: route transition → 2 widget tests
- `TgStatusChip`: online/offline/calling variants → 3 widget tests
- `TgSectionHeader`: with/without count → 2 widget tests
- `TgDeliveryStatus`: 4 states (pending/sent/delivered/read) → 4 widget tests
- `TgCard`: with/without border variants → 2 widget tests
- `TgSkeletonTile` + `TgSkeletonList`: renders placeholders → 2 widget tests
- `TgNavBar`: desktop rail + mobile tabs → 4 widget tests
- Golden: sidebar, conversation panel, desktop layout, dark theme → 4 golden tests
- E2E: `node run.mjs suite` must pass with Telegram-TT selectors
