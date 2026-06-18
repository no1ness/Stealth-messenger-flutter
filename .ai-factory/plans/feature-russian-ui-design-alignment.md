# Русская локализация UI и дизайн-макетов

**Branch:** `feature/russian-ui-design-alignment`
**Created:** 2026-06-17
**Type:** Enhancement / Localization

## Settings

| Параметр | Значение |
|----------|----------|
| Testing | Да — включить тесты для локализации и новых UI-компонентов |
| Logging | Verbose — детальные DEBUG-логи |
| Docs | Да — обязательный чекпоинт документации |
| Roadmap | M10 — Design system v2 (Apple Liquid) |

## Roadmap Linkage

**Milestone:** M10 — Design system v2 (Apple Liquid)
**Rationale:** Русская локализация UI и приведение интерфейса в соответствие с дизайн-макетами — часть финальной полировки M10.

## Фаза 0: Завершение русской локализации UI

Уже переведено 20 файлов (~50% всех строк). Осталось ~180 строк в ~27 файлах.

### T0.1: [x] Перевод оставшихся строк chats_screen.dart

**Файлы:**
- `client/lib/ui/screens/chats_screen.dart`

**Строки:** `'Chat'` (4 fallback), `'Failed to load chats: $error'`, `'Reply'`, `'Unpin message'`/`'Pin message'`, `'Edit'`, `'Delete'`, `'Yesterday'`, `'Chats'` (AppBar + stat), `'Direct'`/`'Local'`, `'Unread'`, `'New group'`, `'No chats'`, `'Selected file is not readable'`, `'Failed to upload attachment'`, `'Voice file is not readable'`, `'Failed to upload voice message'`

### T0.2: [x] Перевод чат-под-экранов

**Файлы:** `chat_search_bar.dart`, `chat_list_panel.dart`, `conversation_panel.dart`, `conversation_footer.dart`, `conversation_attachment.dart`, `insight_panel.dart`, `create_group_sheet.dart`, `group_management_sheet.dart`

**Строки:** ~65 строк:

- **conversation_panel.dart:** `'(edited)'`, `'Search in conversation'`, `'Load older messages'`
- **conversation_footer.dart:** `'Editing'`/`'Replying to'`, `'$messagesCount msgs'`, `'Typing...'`
- **create_group_sheet.dart:** `'Create group chat'`, `'Group name'`, `'Add contacts first'`, `'Unknown'` (fallback), `'Create group'`
- **group_management_sheet.dart:** `'Manage group'`, `'You are an admin. You can manage members and roles.'`, `'You are a member. You can view participants but not change them.'`, `'Members'`, `'Unknown'` (fallback), `'Promote to admin'`, `'Demote to member'`, `'Remove from group'`, `'Add contacts'`, `'No more contacts to add'`, `'Only admins can add members'`, `'Add'`
- **insight_panel.dart:** `'Session insight'`, `'Realtime sync'`/`'Active'`, `'Platform'`/`'Web'`/`'Mobile'`, `'Current user'`/`'Unknown'`, `'Load profile'`
- **chat_search_bar.dart:** `'Search chats'` (hintText)
- **chat_list_panel.dart:** — проверить при наличии файла
- **conversation_attachment.dart:** — проверить при наличии файла

### T0.3: [x] Перевод экранов звонков и диагностики

**Файлы:** `webrtc_call_screen_web.dart`, `webrtc_call_screen_stub.dart`, `webrtc_diagnostics_screen_web.dart`, `webrtc_diagnostics_screen_native_impl.dart`, `webrtc_diagnostics_screen_stub.dart`, `native_call_controller.dart`, `web_call_controller.dart`

**Строки:** ~30 строк — статусы (`'Idle'`, `'Error'`, `'Stopped'`), лейблы (`'Browser WebRTC'`, `'Platform'`), сообщения об ошибках (`'Connection timed out.'`).

### T0.4: [x] Перевод виджетов и хелперов

**Файлы:** `client/lib/ui/sheets/user_detail_sheet.dart`, `client/lib/ui/widgets/empty_state.dart`, `client/lib/themes/apple_liquid/widgets/glass_message_input.dart`, `client/lib/themes/apple_liquid/widgets/glass_chat_bubble.dart`, `client/lib/themes/apple_liquid/widgets/glass_text_field.dart`, `client/lib/themes/apple_liquid/widgets/glass_app_bar.dart`, `client/lib/themes/apple_liquid/widgets/contacts/contact_tile.dart`, `client/lib/themes/apple_liquid/widgets/chats/chat_tile.dart`, `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart`, `client/lib/helpers/date_formatting.dart`, `client/lib/ui/screens/diagnostics/widgets/level_filter_chips.dart`, `client/lib/ui/screens/diagnostics/widgets/service_status_tile.dart`

**Строки:** ~65 строк:

- **user_detail_sheet.dart:** `'Unknown'` (name fallback, line 25), `'Online'`/`'Offline'`, `'Device'`/`'Model'`/`'Platform'`, `'Application'`/`'Version'`, `'Activity'`/`'Registered'`/`'Last seen'`/`'Status'`, `'Write message'`, `'Call'`, `'Edit profile'`
- **empty_state.dart:** `'No conversations yet.'`, `'Send a contact bundle to start a thread. Stealth is silent until you reach out.'`, `'Your address book is private.'`, `'Scan a contact bundle or paste an invite. Nothing leaves the device until you do.'`, `'No calls. Stay silent.'`, `'Outgoing or incoming — your history starts the first time you dial.'`, `'Nothing to see here'` (generic fallback)
- **glass_message_input.dart:** `'Message'` (hintText), `'Recording...'`, `'Stop recording'`/`'Record voice'` (semantic labels, line 172)
- **glass_app_bar.dart:** `'Back'` (tooltip, line 58)
- **level_filter_chips.dart:** `'All'`, `'Warnings'`, `'Errors'` (фильтры уровней, видимы пользователю)
- **contact_tile.dart, chat_tile.dart, call_hud_overlay.dart, date_formatting.dart, service_status_tile.dart:** — проверить при наличии строк (fallback и семантические лейблы)

**Логирование:** `Logger.info('[i18n] translated <file>: <count> strings')` для каждого файла.

### T0.5: [x] Верификация полноты перевода

- `rg -n "(?<![A-Za-z])\'[A-Z][a-z]" lib/ui/ lib/themes/` — поиск оставшихся английских строк
- Проверка семантических лейблов (AccessibilityIds)
- `dart analyze` — нет регрессий

---

## Фаза 1: ChatsScreen — дизайн-макеты

### T1.1: [x] Секционные заголовки Pinned/Recent

**Файлы:** `client/lib/ui/screens/chats_screen.dart`, `client/lib/themes/apple_liquid/widgets/section_header.dart`

- Добавить `SectionHeader` с моноширинным стилем (Geist Mono, 13px/1, `letter-spacing: 2px`, uppercase)
- Добавить count chip numeric badge рядом с заголовком
- Разделить список чатов на Pinned и Recent секции
- Данные: новое поле `isPinned` в модели чата (если отсутствует)

**Логирование:** `Logger.debug('[ui:chats] pinned=<n> recent=<n> section headers rendered')`

### T1.2: [x] Encrypted glyph + delivery ticks в ChatTile

**Файлы:** `client/lib/themes/apple_liquid/widgets/chats/chat_tile.dart`, `client/lib/ui/screens/chats_screen.dart`

- Добавить новые параметры в `ChatTile`: `isSent`, `isRead`, `isDelivered` (все `bool?`), `isVerified` (`bool?`, default `false`), `isPinned` (`bool?`, default `false`)
- Добавить глиф `⌬` (systemGreen) перед текстом preview
- Добавить галочки доставки: `✓` (sent, systemBlue), `✓✓` (read, systemBlue)
- Пробросить значения из `_toUiMessage()` (chats_screen.dart:502-525, поля `isSent`/`isRead`/`isDelivered` уже вычисляются) в `_buildChatTile` вызов `ChatTile()`

**Логирование:** `Logger.debug('[ui:chat-tile] appended delivery status glyphs')`

### T1.3: [x] Gradient avatar + verified badge

**Файл:** `client/lib/themes/apple_liquid/widgets/chats/chat_tile.dart`

- Заменить `CircleAvatar` solid blue на градиент из хэша nickname (детерминированный, как в `ContactTile`)
- Добавить verified badge (иконка `✓` в синем кружке 16px, Positioned bottom-right аватара)
- Badge показывать только если safety number подтверждён (`isVerified` поле в данных)

**Логирование:** `Logger.debug('[ui:chat-tile] gradient avatar for <name> (verified=$isVerified)')`

### T1.4: [x] Large title в GlassAppBar

**Файл:** `client/lib/themes/apple_liquid/widgets/glass_app_bar.dart`

- Реализовать `isLargeTitle` режим: заголовок 28px/1.1 в левой части, padding 8px 20px 14px
- Изменить `preferredSize` динамически (56px для small, 72px для large)
- Обновить `chats_screen.dart` использовать `isLargeTitle: true`

**Логирование:** `Logger.debug('[ui:app-bar] large title mode=$isLargeTitle')`

### T1.5: [x] Search bar с GlassSearchField

---

## Фаза 2: In-Call HUD — дизайн-макеты

### T2.1: [x] Pulsing E2E ENCRYPTED badge

**Файл:** `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart`

- Добавить `AnimationController` с 2.4s циклом (`repeat(reverse: true)`)
- Анимировать box-shadow: от `AppElevation.level4` до `blurRadius * 1.3`
- Сохранить `ScanlineOverlay` поверх

**Логирование:** `Logger.debug('[ui:call-hud] E2E badge pulse animation mounted')`

### T2.2: [x] Safety-number groups под именем

**Файлы:** `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart`, `client/lib/ui/screens/webrtc_call_screen_web.dart`, `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`

- Добавить новый параметр `safetyNumber` (`String?`) в `CallHudOverlay`
- Под именем собеседника добавить fingerprint в формате `A2:5F · 90:1B · 7C:E4 · 31:88`
- Моноширинный текст (Geist Mono, 11px/1.6, `letter-spacing: 1.5px`)
- Пробросить safety number из экранов звонков (получить из `ContactService` по `peerName`)
- Safety number также может отображаться через `DecryptText` анимацию (см. `glass_text_field.dart` паттерн)

**Логирование:** `Logger.debug('[ui:call-hud] safety number groups rendered')`

### T2.3: [x] Telemetry strip

**Файлы:** `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart`, `client/lib/ui/screens/webrtc_call_screen_web.dart`, `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`

- Добавить новый параметр `telemetry` (`Map<String, String>?`) в `CallHudOverlay`
- Нижняя треть: три колонки (Transport, Audio, Latency)
- Моноширинный шрифт 10px/1.4, uppercase label + значение снизу
- Данные: `_nativeController.iceConnectionState`, `_callController.stats` (codec, rtt); передавать как `telemetry: {'Transport': iceState, 'Audio': codec, 'Latency': '${rtt}ms'}`
- Пробросить из экранов звонков (`webrtc_call_screen_web.dart` line 285-318, `webrtc_call_screen_native_impl.dart` line 164-178) в `CallHudOverlay`

**Логирование:** `Logger.debug('[ui:call-hud] telemetry strip: transport=$transport codec=$codec rtt=${rtt}ms')`

### T2.4: [x] Rotating dashed ring на аватаре

**Файл:** `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart`

- Добавить dashed border ring вокруг большого аватара (116px)
- Анимация вращения 24s linear infinite
- Синий цвет `systemBlue` с `opacity: 0.30`

**Логирование:** `Logger.debug('[ui:call-hud] avatar halo dashed ring animation mounted')`

### T2.5: [x] Connection chip с glowing dot

**Файл:** `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart` или `client/lib/themes/apple_liquid/widgets/status_chip.dart`

- Добавить 6px кружок с `box-shadow: 0 0 8px` цвета статуса перед текстом
- Цвет: success (зелёный), warn (оранжевый), danger (красный)

**Логирование:** `Logger.debug('[ui:call-hud] connection chip status=$status')`

---

## Фаза 3: Полировка и отзывчивый интерфейс

### T3.1: [x] SectionHeader — моноширинный стиль + count chip

**Файл:** `client/lib/themes/apple_liquid/widgets/section_header.dart`

- Добавить параметр `count` (int?) для numeric badge
- Моноширинный стиль: Geist Mono, 13px/1, uppercase, letter-spacing 2px
- Count chip: systemBlue pill с 3px glow

### T3.2: [x] GlassAppBar — isLargeTitle функциональный

**Файл:** `client/lib/themes/apple_liquid/widgets/glass_app_bar.dart`

- (см. T1.4 — вынести в отдельную задачу для независимого тестирования)

### T3.3a: [x] Создать CallsScreen

**Файл:** новый `client/lib/ui/screens/calls_screen.dart`

- Создать экран истории звонков (список последних звонков)
- Использовать `StealthEmptyState.calls()` для пустого состояния (уже переведён в T0.4)
- Получать данные из `CallManager` / `LocalAppService.recordIncomingCall` / `LocalAppService.getCallHistory`
- Показывать для каждого звонка: имя собеседника, дату/время, длительность, статус (входящий/исходящий/пропущенный)
- Иконка: `Icons.call_made` (исходящий), `Icons.call_received` (входящий), `Icons.call_missed` (пропущенный)

**Логирование:** `Logger.debug('[ui:calls] call history loaded: $count entries')`

### T3.3b: [x] Добавить Calls таб в навигацию

**Файл:** `client/lib/main_tabs.dart`

- Импортировать `calls_screen.dart` из T3.3a
- Добавить 4-й таб "Звонки" между Contacts и Profile
- Иконка: `Icons.call_outlined` / `Icons.call`
- Сдвинуть Settings на 5-ю позицию
- Обновить количество табов в `GlassBottomNavBar` и `IndexedStack`
- Обновить `GlassBottomNavBarItem` лейблы (уже переведены)

### T3.4: [x] Registration screen — glass-стиль кнопки

**Файл:** `client/lib/registration_screen.dart`

- Заменить `ElevatedButton` на `OutlinedButton` или `GlassButton` с прозрачным фоном и синей обводкой

### T3.5: [x] Empty state — дефолтная action кнопка

**Файл:** `client/lib/ui/widgets/empty_state.dart`

- Добавить дефолтный action для `StealthEmptyState.chats()`: кнопка "Share my contact bundle"
- Использовать существующий `action` параметр

### T3.6: [x] Система адаптивных breakpoints

**Файлы:** все экраны с `LayoutBuilder`

- Создать `client/lib/helpers/responsive_breakpoints.dart` с константами:
  - `mobileMaxWidth: 600`
  - `tabletMaxWidth: 960`
  - `desktopMinWidth: 961`
- Рефакторинг существующих `LayoutBuilder` проверок на константы
- Добавить `OrientationBuilder` где необходимо

**Логирование:** `Logger.debug('[ui:responsive] layout $deviceType width=$width')`

---

## Фаза 4: Документация и тесты

### T4.1: [x] Обновить docs/design-system.md (русская версия)

**Файл:** `docs/design-system.md`

- Русский перевод уже сделан — проверить полноту и актуальность
- Восстановить удалённые разделы (font-subsetting, accessibility contract, component inventory, performance verification), если были утеряны при переводе

### T4.2: [x] Тесты локализации

**Файл:** новый `client/test/i18n/string_coverage_test.dart`

- Проверить что ключевые UI строки переведены на русский
- Использовать `rg` для поиска английских строк в `lib/ui/` и `lib/themes/`
- Assert: 0 английских user-visible строк (кроме `'E2E ENCRYPTED'` и brand-элементов)

### T4.3: [x] Тесты новых UI компонентов

- **T1.1:** `section_header_test.dart` — отображение count chip
- **T1.2:** `chat_tile_test.dart` — проверка глифа шифрования и галочек доставки
- **T2.1:** `call_hud_overlay_test.dart` — pulse анимация
- **T2.3:** `call_hud_overlay_test.dart` — telemetry strip рендеринг
- **T3.6:** `responsive_breakpoints_test.dart` — значения констант

### T4.4: [x] Чекпоинт документации /aif-docs

- Запустить `/aif-docs` для обновления документации
- Проверить `docs/` на актуальность

---

## Commit Plan

| Commit | Задачи | Сообщение |
|--------|--------|-----------|
| C1 ✅ | T0.1–T0.5 | `feat(i18n): complete Russian localization — chats, contacts, widgets, helpers` (`4df9bcf`) |
| C2 ✅ | T1.1–T1.3 | `feat(ui): align chats screen with design mockups — section headers, encrypted glyph, gradient avatars` |
| C3 ✅ | T1.4–T1.5 | `feat(ui): large title GlassAppBar, GlassSearchField in chat search` |
| C4 ✅ | T2.1–T2.5 | `feat(ui): align in-call HUD with design mockups — pulse badge, safety numbers, telemetry, avatar halo` |
| C5 ✅ | T3.1, T3.2, T3.3a, T3.3b, T3.4, T3.5, T3.6 | `feat(ui): polish — SectionHeader style, responsive breakpoints, Calls tab, glass button, empty state action` |
| C6 | T4.1–T4.4 | `docs(tests): localization tests, UI component tests, docs checkpoint` |
