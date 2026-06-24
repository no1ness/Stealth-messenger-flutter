# Telegram-tt Design Port

**Branch:** `feature/telegram-tt-design`
**Created:** 2026-06-22
**Type:** refactor

## Описание

Полноценная миграция дизайна Stealth Messenger с `apple_liquid` (glassmorphism, Geist-шрифты,
Apple-палитра) на плоский дизайн Telegram Web Z (telegram-tt) с Roboto/системными шрифтами,
Telegram-палитрой и iMessage-подобными пузырьками.

**Источник:** https://github.com/Ajaxy/telegram-tt (73+ цветовых токена в themes.json,
120+ CSS-переменных в _variables.scss)

**Что меняется:**
- Цветовая палитра: `AppColors` → `TgColors` (синий `#3390EC`, зелёный `#00C73E`,
  фиолетовый primary в тёмной теме `#8774E1`)
- Шрифты: Geist/Geist Mono → Roboto + system-ui fallback (iOS: system-ui, остальные: Roboto)
- Виджеты: все Glass* → плоские Material-виджеты, стилизованные под Telegram
- Эффекты: ScanlineOverlay, GrainOverlay, ChromaticAberration, CircuitBoardBackground → удалить
- Анимации: кастомные (DecryptText, StaggeredListView, AppMotion) → стандартные Material
- Навигация: GlassPageRoute → стандартные MaterialPageRoute
- Фон: StealthAnimatedBackground → `TgColors.background`
- Иконки: Material Icons (оставить как есть, ~85 иконок)

## Settings

- Testing: yes (golden-тесты для ключевых компонентов)
- Logging: verbose (DEBUG-логи на этапе замены)
- Docs: yes (обновить docs/design-system.md)
- Constraints: сохранить структуру экранов, менять только тему/виджеты

## Tasks

### Phase 1 — Фундамент

#### Task 1: Токены цветов Telegram (TgThemeColors)

- [x] **DONE** — создан класс `TgThemeColors` с ~76 цветовыми токенами (light/dark)

Заменить `themes/tg/tg_colors.dart`:

- Создать новый класс `TgThemeColors` с полным набором ~80+ цветовых токенов
- Источник: `themes.json` (light/dark пары) + `_variables.scss` (дополнительные переменные)
- Каждый геттер возвращает `Color` на основе `Brightness`
- Паттерн: кэшируемый per-Brightness (как сейчас), **без ThemeExtension** (static-класс проще)
- Цвета перевести из hex (8-digit с alpha) в Flutter `Color`

**Files:** `client/lib/themes/tg/tg_colors.dart`
**Logging:** debug-level: "TgThemeColors: initialized 80+ color tokens"

#### Task 2: Полноценная Material-тема (TgThemeData)

- [x] **DONE** — обновлён `TgThemeData` с полным ThemeData (appBar, card, chip, bottomNav, input, dialog, snackBar, switch)

Заменить `themes/tg/tg_theme_data.dart`:

- Полноценный `ThemeData` (light/dark) с Telegram-цветами
- `colorScheme` из `TgThemeColors`
- `textTheme` с Roboto (Geist больше не используется)
- `appBarTheme`, `cardTheme`, `chipTheme`, `bottomNavigationBarTheme`,
  `inputDecorationTheme`, `dialogTheme`, `snackBarTheme`, `switchTheme`
- `scaffoldBackgroundColor: TgThemeColors.background`
- Все настраиваемые слоты Material, чтобы экраны не импортировали
  кастомные константы

**Files:** `client/lib/themes/tg/tg_theme_data.dart`
**Logging:** debug-level: "TgThemeData: light/dark fully configured"

#### Task 3: Базовая типографика

- [x] **DONE** — создан `TgTypography` с 22 именованными стилями + textTheme
- [ ] **(pending)** — заменить шрифты в pubspec.yaml (Geist→Roboto), удалить geist-ассеты (требуются font-файлы Roboto Mono)

Настроить `textTheme`:

- Загрузить Roboto + Roboto Mono (заменить Geist/Geist Mono в pubspec.yaml)
- Удалить Geist/Geist Mono ассеты из `assets/fonts/`
- Создать `TgTypography` с именованными стилями (как сейчас `AppTypography`),
  но использующий Roboto
- **Платформенные шрифты:** на iOS/macOS использовать `system-ui` (через `defaultTargetPlatform`),
  на Android/Web/Linux/Windows — Roboto
- **Полный маппинг 22→22 стилей:**

| AppTypography | TgTypography | Material textTheme |
|---|---|---|
| `largeTitle` | `largeTitle` | `headlineMedium` |
| `title1` | `title1` | `titleLarge` |
| `title2` | `title2` | `titleMedium` |
| `title3` | `title3` | `titleSmall` |
| `headline` | `headline` | `titleLarge` |
| `body` | `body` | `bodyMedium` |
| `bodyEmphasis` | `bodyEmphasis` | `bodyMedium` + w600 |
| `callout` | `callout` | `bodyLarge` |
| `calloutEmphasis` | `calloutEmphasis` | `bodyLarge` + w600 |
| `subheadline` | `subheadline` | `bodySmall` |
| `subheadlineEmphasis` | `subheadlineEmphasis` | `bodySmall` + w600 |
| `footnote` | `footnote` | `labelMedium` |
| `footnoteEmphasis` | `footnoteEmphasis` | `labelMedium` + w600 |
| `caption1` | `caption1` | `bodySmall` |
| `caption1Emphasis` | `caption1Emphasis` | `bodySmall` + w600 |
| `caption2` | `caption2` | `labelSmall` |
| `caption2Emphasis` | `caption2Emphasis` | `labelSmall` + w600 |
| `captionMono` | `captionMono` | `bodySmall` + monospace |
| `titleMono` | `titleMono` | `titleSmall` + monospace |
| `fontFamily` | `fontFamily` | `'Roboto', 'system-ui'` |
| `fontFamilyMono` | `fontFamilyMono` | `'Roboto Mono', monospace` |

**Files:**
- `client/pubspec.yaml` (шрифты)
- `client/lib/themes/tg/tg_typography.dart` (новый файл)
- Удалить `client/assets/fonts/geist/` и `client/assets/fonts/geist-mono/`
**Logging:** info: "TgTypography: migrated from Geist to Roboto"

#### Task 4: TgSpacing (константы отступов)

- [x] **DONE** — создан `TgSpacing` с 6-tier scale + радиусы + UI-константы

Создать класс `TgSpacing` — аналог `AppSpacing` на telegram-tt rem-шкале:

- 6-tier scale: `xxs` (4px), `xs` (8px), `sm` (12px), `md` (16px), `lg` (20px), `xl` (24px), `xxl` (32px)
- Telegram-specific: `huge` (48px), `massive` (64px)
- Радиусы: `radiusXs` (4px), `radiusSm` (8px), `radiusMd` (12px), `radiusLg` (16px), `radiusXl` (20px), `radiusRound` (999px)
- UI-константы: `buttonHeight` (44px), `buttonHeightSmall` (32px), `iconSm` (20px), `iconMd` (24px), `iconLg` (32px), `bottomBarOverlap` (80px), `screenEdge` (16px)

**Files:** `client/lib/themes/tg/tg_spacing.dart`
**Logging:** debug: "TgSpacing: 6-tier scale created"

### Phase 2 — Базовые компоненты

#### Task 5: FlatContainer (замена GlassContainer)

- [x] **DONE** — создан `flat_container.dart` с FlatContainer, FlatCard, FlatButton

Создать простой `FlatContainer` вместо `GlassContainer`:

- Убрать glass-эффекты (BackdropFilter, blur, gradient glass)
- Использовать `TgThemeColors.surface` (или `cardBackground`) фон + `TgSpacing` для отступов
- `borderRadius: 12` (Telegram default)
- Небольшая тень (`TgThemeColors.defaultShadow`)
- `FlatCard` и `FlatButton` как простые обёртки над Material `Card` / `ElevatedButton`

**Files:**
- `client/lib/themes/tg/components/flat_container.dart` (новый)
- `client/lib/themes/tg/components/flat_card.dart` (новый)
- `client/lib/themes/tg/components/flat_button.dart` (новый)
**Logging:** debug: "FlatContainer: no-op glass removal"

#### Task 6: FlatAppBar (замена GlassAppBar)

- [x] **DONE** — создан `tg_app_bar.dart` с TgAppBar + TgSliverAppBar

Создать `TgAppBar`:

- Обычный `AppBar` (Material), backgroundColor `TgThemeColors.backgroundSecondary`
- elevation: 0 (плоский)
- title: Telegram-style (medium weight, 17px)
- Никакого glass/размытия
- `TgSliverAppBar` как обёртка `SliverAppBar`

**Files:**
- `client/lib/themes/tg/widgets/tg_app_bar.dart` (новый)
**Logging:** debug: "TgAppBar: flat AppBar created"

#### Task 7: BottomNavBar (замена GlassBottomNavBar)

- [x] **DONE** — создан `tg_bottom_nav_bar.dart` с TgBottomNavBar + TgBottomNavBarItem

Создать `TgBottomNavBar`:

- Material `NavigationBar` или кастомный BottomAppBar
- Telegram-стиль: иконка + лейбл, активный — primary цвет
- Плоский фон `TgThemeColors.backgroundSecondary`

**Files:**
- `client/lib/themes/tg/widgets/tg_bottom_nav_bar.dart` (новый)
**Logging:** debug: "TgBottomNavBar: flat nav bar created"

#### Task 8: ChatBubble (замена GlassChatBubble)

- [x] **DONE** — создан `tg_chat_bubble.dart` с TgChatBubble (TgMessageType.sent/received)

Создать `TgChatBubble`:

- iMessage-стиль: sent = `TgThemeColors.backgroundOwn` (зелёный light,
  фиолетовый dark), received = `TgThemeColors.background` (белый light,
  тёмно-серый dark)
- `borderRadius: 15` (как telegram-tt `--border-radius-messages: 0.9375rem`)
- Никаких scanline/grain эффектов
- `TgMessageType.sent` / `TgMessageType.received`
- Время/статус внутри бабла (серый текст внизу справа)
- Учесть `outgoing_delivery_status_icon.dart` — перенести его на TgThemeColors

**Files:**
- `client/lib/themes/tg/widgets/tg_chat_bubble.dart` (новый)
- `client/lib/ui/widgets/outgoing_delivery_status_icon.dart` (обновить импорты)
**Logging:** debug: "TgChatBubble: flat iMessage-style bubble"

#### Task 9: TgChatTile

- [x] **DONE** — создан `tg_chat_tile.dart` с TgChatTile

Создать `TgChatTile` — замена кастомного `ChatTile`:

- Стандартный `ListTile` с Telegram-цветами
- Аватар (40×40), название, последнее сообщение, время, счётчик непрочитанных
- `TgThemeColors.backgroundSecondary` для фона, `TgThemeColors.textPrimary` для текста
- Без glass-эффектов

**Files:**
- `client/lib/themes/tg/widgets/tg_chat_tile.dart` (новый)
**Logging:** debug: "TgChatTile: flat list tile created"

#### Task 10: TgContactTile

- [x] **DONE** — создан `tg_contact_tile.dart` с TgContactTile

Создать `TgContactTile` — замена кастомного `ContactTile`:

- Стандартный `ListTile` с Telegram-цветами
- Аватар, имя, статус, action-иконки
- `TgThemeColors.textPrimary` / `TgThemeColors.textSecondary`

**Files:**
- `client/lib/themes/tg/widgets/tg_contact_tile.dart` (новый)
**Logging:** debug: "TgContactTile: flat contact tile created"

#### Task 11: TgSectionHeader

- [x] **DONE** — создан `tg_section_header.dart` с TgSectionHeader

Создать `TgSectionHeader` — простая замена `SectionHeader`:

- Обычный `Text` с `TgTypography.bodyEmphasis` (или заголовок с жирным шрифтом)
- Padding из `TgSpacing` (md horizontal, xs vertical)
- Опционально: uppercase + серый цвет (как telegram-tt секции)

**Files:**
- `client/lib/themes/tg/widgets/tg_section_header.dart` (новый)
**Logging:** debug: "TgSectionHeader: flat section header created"

#### Task 12: TextField / SearchField (замена GlassTextField / GlassSearchField)

- [x] **DONE** — создан `tg_text_field.dart` с TgTextField + TgSearchField

Создать `TgTextField` и `TgSearchField`:

- Material `TextField` с Telegram-стилем
- `borderRadius: 10`, `TgThemeColors.bordersInput` цвет рамки
- Фокус: primary цвет рамки (без ChromaticAberration)
- `TgSearchField` — `TextField` с prefix search icon

**Files:**
- `client/lib/themes/tg/widgets/tg_text_field.dart` (новый)
**Logging:** debug: "TgTextField: flat text field created"

#### Task 13: MessageInput (замена GlassMessageInput)

- [x] **DONE** — создан `tg_message_input.dart` с TgMessageInput

Создать `TgMessageInput`:

- Material `TextField` + кнопки (attach, voice, send)
- Фон `TgThemeColors.backgroundSecondary`, скруглённый контейнер
- Та же функциональность (текст, аттачмент, голосовая запись)
- Убрать glass-эффекты

**Files:**
- `client/lib/themes/tg/widgets/tg_message_input.dart` (новый)
**Logging:** debug: "TgMessageInput: flat composer created"

#### Task 14: Feedback (SnackBar, Dialog, Loading)

- [x] **DONE** — созданы `tg_snack_bar.dart`, `tg_dialog.dart`, `tg_loading.dart`, `tg_haptics.dart`

Переписать `showStealthSnackBar` / `showStealthDialog` под Telegram-стиль:

- SnackBar: Material SnackBar с `TgThemeColors.toastBackground`
- Dialog: Material AlertDialog с `TgThemeColors.background`, `borderRadius: 16`
- Loading: `Center + CircularProgressIndicator` (вместо StealthLoadingIndicator)
- Skeleton: shimmer-эффект (можно оставить или убрать)
- **stealth_haptics.dart** — перенести логику вибрации в новый файл (без привязки к apple_liquid)

**Files:**
- `client/lib/themes/tg/feedback/tg_snack_bar.dart` (новый)
- `client/lib/themes/tg/feedback/tg_dialog.dart` (новый)
- `client/lib/themes/tg/feedback/tg_loading.dart` (новый)
- `client/lib/themes/apple_liquid/feedback/stealth_snack_bar.dart` (удалить)
- `client/lib/themes/apple_liquid/feedback/stealth_dialog.dart` (удалить)
- `client/lib/themes/apple_liquid/feedback/stealth_loading_indicator.dart` (удалить)
- `client/lib/themes/apple_liquid/feedback/stealth_skeleton.dart` (удалить)
- `client/lib/themes/tg/feedback/tg_haptics.dart` (новый — перенос логики вибрации)
**Logging:** info: "TgFeedback: all feedback widgets migrated"

### Phase 3 — Миграция экранов (по одному)

#### Task 15: Barrel-файл темы (TgThemeExports)

- [x] **DONE** — создан `tg_theme_exports.dart`

Создать `themes/tg/tg_theme_exports.dart`, который экспортирует:

- `TgThemeColors` (все цвета)
- `TgTypography` (все стили)
- `TgSpacing` (константы отступов)
- Все новые виджеты: TgAppBar, TgBottomNavBar, TgChatBubble, TgChatTile, TgContactTile,
  TgSectionHeader, FlatContainer, TgTextField, TgSearchField, TgMessageInput, FlatButton, FlatCard
- Все feedback-виджеты: TgSnackBar, TgDialog, TgLoading

**Files:** `client/lib/themes/tg/tg_theme_exports.dart`
**Примечание:** выполняется после завершения Phase 2 (Task 5–14), т.к. экспортирует все компоненты.

#### Task 16: main_tabs.dart — замена на TgBottomNavBar

- Импортировать `tg_theme_exports.dart` (вместо `theme_exports.dart`)
- `TgBottomNavBar` вместо `GlassBottomNavBar`
- Убрать `StealthAnimatedBackground` (просто Scaffold с `TgThemeColors.background`)
- `DebugStatusBar` — обновить импорты на TgTypography/TgSpacing

#### Task 17: loading_screen.dart

- `StealthAnimatedBackground` → простой Scaffold
- `CircuitBoardBackground` → убрать (больше не нужен)
- `DecryptText` → обычный Text с анимацией fade
- `GlassContainer` → `FlatContainer` / просто Container
- `AppColors.*` → `TgThemeColors.*`
- `AppSpacing.*` → `TgSpacing.*`
- `AppTypography.*` → `TgTypography.*`
- `AppMotion.*` → стандартные 300ms

#### Task 18: settings_screen.dart

- `GlassAppBar` → `TgAppBar`
- `GlassContainer` → `FlatContainer` / Card
- `AppColors.*` → `TgThemeColors.*`
- `AppSpacing.*` → `TgSpacing.*`
- `AppTypography.*` → `TgTypography.*`
- `SectionHeader` → `TgSectionHeader`
- `StealthLoadingIndicator` → `TgLoading` (CircularProgressIndicator)
- `showStealthSnackBar` → `TgSnackBar.show()`

#### Task 19: contacts_screen.dart

- `GlassAppBar` → `TgAppBar`
- `GlassTextField` → `TgSearchField`
- `AppColors.*` → `TgThemeColors.*`
- `AppSpacing.*` → `TgSpacing.*`
- `AppTypography.*` → `TgTypography.*`
- `ContactTile` → `TgContactTile`
- `showStealthSnackBar` → `TgSnackBar.show()`
- `GlassPageRoute.modal` → MaterialPageRoute

#### Task 20: profile_screen.dart

- `GlassAppBar` → `TgAppBar`
- `GlassContainer` → `FlatContainer` / Card
- `AppColors.*` → `TgThemeColors.*`
- `AppTypography.*` → `TgTypography.*`
- `StealthLoadingIndicator` → `TgLoading`

#### Task 21: calls_screen.dart

- `GlassAppBar` → `TgAppBar`
- `AppTypography.*` → `TgTypography.*`

#### Task 22: monitoring_screen.dart

- `GlassAppBar` → `TgAppBar`
- `GlassContainer` → `FlatContainer`
- `SectionHeader` → `TgSectionHeader`
- `AppSpacing.*` → `TgSpacing.*`
- `AppTypography.*` → `TgTypography.*`
- `StealthLoadingIndicator` → `TgLoading`

#### Task 23: chats_screen.dart + sub-screens (chat_list_panel, conversation_attachment, group_management_sheet, insight_panel)

- `GlassAppBar` → `TgAppBar`
- `ChatTile` → `TgChatTile`
- `AppColors.*` → `TgThemeColors.*`
- `AppSpacing.*` → `TgSpacing.*`
- `AppTypography.*` → `TgTypography.*`
- `showStealthSnackBar` → `TgSnackBar.show()`
- `SectionHeader` → `TgSectionHeader`
- Явные файлы:
  - `ui/screens/chats/chat_list_panel.dart`
  - `ui/screens/chats/conversation_attachment.dart`
  - `ui/screens/chats/group_management_sheet.dart`
  - `ui/screens/chats/insight_panel.dart`

#### Task 24: conversation_panel.dart + footer + search

- `GlassChatBubble` → `TgChatBubble`
- `GlassMessageInput` → `TgMessageInput`
- `GlassSearchField` → `TgSearchField`
- `AppColors.*` → `TgThemeColors.*`
- `AppSpacing.*` → `TgSpacing.*`

#### Task 25: telegram_sidebar.dart + telegram_header.dart

- `GlassSearchField` → `TgSearchField`
- `ChatTile` → `TgChatTile`
- `AppColors.*` → `TgThemeColors.*`
- `AppTypography.*` → `TgTypography.*`
- `AppSpacing.*` → `TgSpacing.*`

#### Task 26: diagnostics screens (diagnostics_screen + widgets: level_filter_chips, log_entry_tile, service_status_tile, performance_monitor + diagnostics_share)

- `GlassAppBar` → `TgAppBar`
- `GlassContainer` → `FlatContainer`
- `GlassButton` → `ElevatedButton` / `FlatButton`
- `SectionHeader` → `TgSectionHeader`
- `AppColors.*` → `TgThemeColors.*`
- `AppTypography.*` → `TgTypography.*`
- `AppSpacing.*` → `TgSpacing.*`
- `StealthAnimatedBackground` → убрать
- Явные файлы:
  - `ui/screens/diagnostics/diagnostics_screen.dart`
  - `ui/screens/diagnostics/widgets/level_filter_chips.dart`
  - `ui/screens/diagnostics/widgets/log_entry_tile.dart`
  - `ui/screens/diagnostics/widgets/service_status_tile.dart`
  - `ui/screens/diagnostics/widgets/performance_monitor.dart`
  - `services/diagnostics/diagnostics_share.dart`

#### Task 27: webrtc screens

- `GlassAppBar` → `TgAppBar`
- `GlassContainer` → `FlatContainer`
- `CallHudOverlay` — оставить, но убрать ScanlineOverlay + обновить AppColors на TgThemeColors
- `StealthAnimatedBackground` → убрать
- `StatusChip` → стандартный Chip
- `AppColors.*` → `TgThemeColors.*`
- `AppTypography.*` → `TgTypography.*`
- `AppSpacing.*` → `TgSpacing.*`

#### Task 28: registration_screen.dart + startup_error.dart

- `StealthAnimatedBackground` → убрать
- `GrainOverlay` → убрать
- `GlassContainer` → FlatContainer
- `AppColors.*` → `TgThemeColors.*`
- `AppTypography.*` → `TgTypography.*`
- `AppSpacing.*` → `TgSpacing.*`

#### Task 29: Остальные файлы (call_manager, user_detail_sheet, empty_state, chat_bubble, message_input, voice_message_player, outgoing_delivery_status_icon)

- `GlassPageRoute` → MaterialPageRoute
- `showStealthSnackBar` → `TgSnackBar.show()`
- `showStealthDialog` → `TgDialog.show()`
- `GrainOverlay` (в empty_state) → убрать
- `AppColors.*` → `TgThemeColors.*`
- `AppTypography.*` → `TgTypography.*`
- `AppSpacing.*` → `TgSpacing.*`
- Явные файлы:
  - `ui/widgets/call_manager.dart`
  - `ui/sheets/user_detail_sheet.dart`
  - `ui/widgets/empty_state.dart`
  - `ui/widgets/chat_bubble.dart`
  - `ui/widgets/message_input.dart`
  - `ui/widgets/voice_message_player.dart`
  - `ui/widgets/outgoing_delivery_status_icon.dart`

#### Task 30: dashboard_home_screen.dart

- `AppColors.*` → `TgThemeColors.*`
- `AppSpacing.*` → `TgSpacing.*`
- `AppTypography.*` → `TgTypography.*`

**Files:** `client/lib/ui/screens/dashboard/dashboard_home_screen.dart`

#### Task 31: update_prompt_screen.dart + update_status_card.dart

- `GlassContainer` → `FlatContainer`
- `AppColors.*` → `TgThemeColors.*`
- `AppTypography.*` → `TgTypography.*`
- `AppSpacing.*` → `TgSpacing.*`

**Files:**
- `client/lib/ui/screens/app_update/update_prompt_screen.dart`
- `client/lib/ui/screens/app_update/update_status_card.dart`

#### Task 32: diagnostics_share.dart

- `AppColors.*` → `TgThemeColors.*`
- `showStealthSnackBar` → `TgSnackBar.show()`

**Files:** `client/lib/services/diagnostics/diagnostics_share.dart`

### Phase 4 — Чистка

#### Task 33: Удалить apple_liquid

- Удалить директорию `themes/apple_liquid/`
- Удалить эффекты: `effects/scanline_overlay.dart`, `effects/grain_overlay.dart`,
  `effects/chromatic_aberration.dart`
- Удалить motion: `motion/decrypt_text.dart`, `motion/staggered_list_view.dart`
- Удалить navigation: `navigation/glass_page_route.dart`
- Удалить screens: `screens/liquid_*.dart`

**Перед удалением убедиться, что ни один файл вне `themes/apple_liquid/`
не импортирует `theme_exports.dart`.** (39 файлов → все должны быть переведены на `tg_theme_exports.dart`)

#### Task 34: Обновить main.dart

- `TgThemeData.light` / `TgThemeData.dark` уже подключены (TgThemeData будет
  расширен в Task 2)
- Убедиться, что `themeModeProvider` корректно работает с обновлённой темой

### Phase 5 — Тесты и документация

#### Task 35: Golden-тесты для новых компонентов

- Создать golden-тесты для ключевых компонентов:
  - `TgChatBubble` (sent + received)
  - `TgAppBar`
  - `TgBottomNavBar`
  - `TgSearchField`
- Использовать `golden_toolkit` (уже в dev_dependencies)

**Files:**
- `client/test/themes/tg/widgets/tg_chat_bubble_test.dart`
- `client/test/themes/tg/widgets/tg_app_bar_test.dart`
- `client/test/themes/tg/widgets/tg_bottom_nav_bar_test.dart`
- `client/test/themes/tg/widgets/tg_search_field_test.dart`

#### Task 36: Обновить design-system.md

- Полностью переписать `docs/design-system.md` под Telegram-tt дизайн
- Описать новую цветовую палитру
- Описать типографику (Roboto + system-ui на iOS)
- Описать паттерны (плоский дизайн, iMessage-баблы, Material Icons)
- Удалить упоминания apple_liquid, glass-эффектов, Geist
- Добавить раздел производительности (telegram-tt оптимизирован для скорости)

**Files:** `docs/design-system.md`, `docs/design-mockups/` (если нужно)

#### Task 37: Финальная сборка и верификация

- `flutter build web --release` — проверить, что собирается
- `flutter analyze` — проверить, что нет ошибок
- `flutter test` — проверить, что тесты проходят

## Commit Plan

| # | Коммит | Задачи |
|---|--------|--------|
| 1 | ✅ `feat(theme): Phase 1 - TgThemeColors, TgThemeData, TgSpacing, fix flutter_webrtc` (5dd7e2d) | 1, 2, 4 |
| 2 | `refactor(theme): add Roboto typography, replace Geist` (pending font assets) | 3 |
| 3 | ✅ `feat(theme): add flat Telegram-style base widgets` (49a3867) | 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 |
| 4 | ✅ `refactor(theme): create TgThemeExports barrel` (4623cb0) | 15 |
| 5 | ✅ `refactor(ui): migrate screens 16-21 to Telegram theme` (4623cb0) | 16, 17, 18, 19, 20, 21 |
| 6 | ✅ `refactor(ui): migrate screens 22-25 to Telegram theme` (4623cb0) | 22, 23, 24, 25 |
| 7 | ✅ `refactor(ui): migrate screens 26-32 to Telegram theme` (4623cb0) | 26, 27, 28, 29, 30, 31, 32 |
| 8 | `chore(theme): remove apple_liquid theme and effects` | 33, 34 |
| 9 | `test(theme): add golden tests for Telegram widgets` | 35 |
| 10 | `docs(theme): update design-system.md for Telegram-tt` | 36 |
| 11 | `chore: final build verification` | 37 |
