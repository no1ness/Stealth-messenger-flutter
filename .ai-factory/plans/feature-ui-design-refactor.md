# UI design refactor: aesthetic direction + design-system + миграция всех экранов

**Branch:** `feature/ui-design-refactor` (от `main`, без worktree)
**Created:** 2026-05-18
**Refined:** 2026-05-18 — applied `frontend-design@claude-plugins-official` (pass 1) + practical execution audit (pass 2: accessibility/perf/licensing/infra)
**Slug:** `ui-design-refactor`

## Settings

- **Testing:** yes — widget-тесты на новые reusable widgets + smoke-регрессии на каждом мигрируемом экране + golden-test visual reel (Phase 9)
- **Logging:** verbose — `Logger.debug` / `debugPrint` в новых widget-фабриках (snackbar/dialog/route/haptics/effects) для отладки UX-флоу; `Logger.info` для key UX событий (theme switch, route push, haptic trigger, signature effect mount)
- **Docs:** yes — обязательный docs-checkpoint в конце; `docs/design-system.md` (новый, главный артефакт) и UI-секция `docs/ARCHITECTURE.md`

## Контекст

Текущее состояние UI (по реконнaссансу на `main`):

- **Дизайн-система `client/lib/themes/apple_liquid/`** — solid foundation: `AppColors`, `AppSpacing`, `AppTypography` (декларирует SF Pro но фонты не подключены в `pubspec.yaml` — fallback на system fonts), `GlassStyles`, `GlassContainer`, `GlassAppBar`, `GlassBottomNavBar`, `GlassTextField`, `GlassChatBubble`, `GlassMessageInput`, `StealthAnimatedBackground`. Coverage ~85 %.
- **Пять перегруженных экранов:** `chats_screen.dart` (1159), `contacts_screen.dart` (731), `profile_screen.dart` (682), `settings_screen.dart` (478), `webrtc_call_screen_native_impl.dart` (406).
- **Missing primitives:** нет `SectionHeader`, `ListDivider`, нет helper'а для snackbar/dialog, `EmptyState` читает `Theme.colorScheme` вместо `AppColors`, нет motion/elevation/effects/haptics токенов, все навигации — `MaterialPageRoute`.
- **Нет тактильной обратной связи:** `grep haptic client/lib` → 0 матчей.
- **Шрифты — fiction:** `AppTypography` ссылается на SF Pro, но `pubspec.yaml` секция `fonts:` закомментирована — реально system fallback'и.
- **AccessibilityIds под жёстким контрактом:** `client/lib/constants/accessibility_ids.dart` — "single source of truth for all Semantics wrappers" + завязан на Appium suite ("Do NOT change values"). Существующие экраны имеют 12+ `Semantics()` обёрток (contacts: 9, chats: 2, nav bar: 1). Извлечение widget'ов должно сохранить контракт.
- **Нет `RepaintBoundary`:** `grep RepaintBoundary client/lib` → 0 матчей. Добавление scan-line/grain overlays + stagger без боундерей провалит framerate на старых Android и web (Skia).
- **Settings без theme-toggle UI:** `ThemeMode` персистится, но UI отсутствует.
- **Material icons по умолчанию.**
- **Нет signature visual moments:** Stealth выглядит как "generic glass messenger".

Цель: **commit to a bold aesthetic direction** + новые signature elements + миграция всех экранов на reusable primitives + не сломать accessibility/perf/licensing.

## Совместимость с `feature/hardening-di-secure-storage`

Ветка от `main`. Hardening содержит Riverpod DI, safety-number dialog, "Rotate identity key" button, `ConsumerStatefulWidget` миграцию.

При итоговом merge **обе ветки конфликтнут на тех же экранах**. Разрешение:

- Принимать `ConsumerStatefulWidget` / `ref.read(provider)` из hardening
- Принимать новые widget-обёртки (`SectionHeader`, `StealthSnackBar`, `StealthDialog`, `StealthHaptics`, эффекты) из дизайн-рефактора
- Safety-number и rotation UI из hardening пересобрать поверх `StealthDialog`/`SectionHeader` после merge
- Theme-toggle из дизайн-ветки (`ValueNotifier`) при merge переключить на `themeModeProvider` (Riverpod)

## Phase 0 — Aesthetic direction, fonts (with licensing gate), tokens, signature effects

### 0.1 Commit to an aesthetic direction (NORTH STAR)

- Файл: `docs/design-system.md` (новый, opening section).
- Frontend-design: "Choose a clear conceptual direction and execute it with precision."
- Опции (выбрать одну в имплементации):
  - **Refined crypto-noir (рекомендуется):** stealth dark (#0A0E1A) + sharp blue (#007AFF) + selective desaturated cyan, monospace numerics, signature scan-line на glass surfaces, dramatic blue glow accents.
  - **Editorial security:** display serif + grotesque body, много negative space, минимум градиентов, контраст через типографику и асимметричный grid.
  - **Industrial brutalist:** raw concrete, плотные monospace блоки, плакатные акценты.
- Зафиксировать выбор + 3-5 inspirational references (linkов) в `docs/design-system.md → Aesthetic direction`.
- Логирование: N/A (документ).

### 0.2 Select custom fonts (replace SF Pro stub)

- Файлы: `client/pubspec.yaml`, `client/lib/themes/apple_liquid/constants/app_typography.dart`, `client/assets/fonts/` (новая папка).
- Контекст: `AppTypography` декларирует SF Pro но `pubspec.yaml fonts:` закомментирована → грузятся system fallback'и (Roboto/SF/Liberation). Frontend-design: "Avoid generic fonts."
- **По выбранному направлению (0.1) подобрать font pair:**
  - Crypto-noir: **Geist Mono** (monospace, OFL/MIT через Vercel) + **Geist Sans** или **Inter Tight** (body, OFL).
  - Editorial security: **Söhne** или **Neue Haas Grotesk** (body, commercial — verify license в 0.3) + **Tiempos** или **GT Sectra** (display serif, commercial).
  - Industrial brutalist: **JetBrains Mono** (OFL) + **Space Grotesk** (OFL — но frontend-design предостерегает от overuse; использовать с осторожностью).
- **Fallback ladder:** в `pubspec.yaml` указать минимум 2 weights (Regular 400 + Medium/Semibold 500-600 + Bold 700). Добавить `AppFontStacks` const с fallback ladder'ами на случай если файл шрифта не загрузился ("display → body → sans-serif").
- **Multi-platform load test:** перед merge'ем фазы — `flutter run -d <android>`, `flutter run -d chrome`, проверить что шрифт реально применился (font-feature support varies — особенно variable axes на web).
- Логирование: `Logger.info('[fonts] loaded family=$family')` при первом mount'е.

### 0.3 Font licensing verification + asset budget gate

- **Блокирующая задача** — без неё не качаем ни одного шрифта.
- **Verification:** для каждого шрифта из 0.2 проверить:
  - License file (OFL.txt, LICENSE.txt) разрешает redistribution в open-source приложении.
  - Geist / Inter / JetBrains Mono / Space Grotesk — OFL/MIT, разрешено.
  - Söhne / Berkeley Mono / Tiempos / GT Sectra — paid commercial, требуется приобретённая лицензия + явное разрешение на bundling в Flutter app. **Без покупки — выбрать OFL-альтернативу.**
- **Asset budget:**
  - Subset шрифты до Latin Extended + common punctuation через `pyftsubset` (fonttools) или font-subset CLI. Целевой размер per weight: ≤ 80 KB.
  - Бюджет на initial app: web bundle ≤ +600 KB всего fonts, mobile ≤ +1.5 MB всего fonts.
  - Если бюджет превышен — drop unused weights (italic, light, black).
- Документировать licensing chain + размеры в `docs/design-system.md → Fonts → Licensing & budgets`.
- Логирование: N/A (one-shot задача).

### 0.4 Token audit + extension (constants/)

- Файлы: `client/lib/themes/apple_liquid/constants/app_colors.dart`, `app_spacing.dart`, `app_typography.dart`, `glass_styles.dart`.
- **Аудит:** перечислить все magic numbers (blur σ, opacity, durations, паддинги) в widgets и решить, какие достойны попасть в constants.
- **Добавить новые constants файлы:**
  - `app_motion.dart` — durations (`fast: 150ms`, `normal: 250ms`, `slow: 400ms`, `pageRoute: 320ms`) + curves (`emphasized`, `standard`, `decelerated`).
  - `app_elevation.dart` — depth tokens (`level0..level4`) — `BoxShadow` + `blurRadius` пресеты для glass cards и dialogs.
  - `app_effects.dart` — `grainOpacity` (default 0.04), `scanlineOpacity` (0.06), `scanlineSpacingPx` (4), `aberrationDxPx` (1.5).
  - `app_haptics.dart` — `HapticIntensity` enum → `HapticFeedback.*` mapping.
- **Доработать `AppSpacing`:** `screenEdge`, `cardPadding`, `tileGap`, `bottomBarOverlap`, `buttonHeight`.
- **Доработать `AppColors`:** WCAG AA проверка (≥ 4.5 body, ≥ 3 large). Семантические алиасы (`textPrimary/Secondary/OnGlass`, `dividerSubtle`, `statusSuccess/Warn/Danger/Info`).
- Логирование: N/A.

### 0.5 Signature visual effects (`ScanlineOverlay`, `GrainOverlay`)

- Папка: `client/lib/themes/apple_liquid/effects/`.
- Frontend-design: "What makes this UNFORGETTABLE?"
- **`scanline_overlay.dart`:** `CustomPaint` рисующий горизонтальные scan-lines с opacity из `AppEffects.scanlineOpacity` и spacing `scanlineSpacingPx`. API: `ScanlineOverlay({ Widget child, double intensity = 1.0, bool force = false })`. **Обязательно** обёрнут в `RepaintBoundary` (см. 1.11).
- **`grain_overlay.dart`:** noise texture через `CustomPaint` (procedural). API: `GrainOverlay({ Widget child, double opacity, bool force = false })`. Также в `RepaintBoundary`.
- **`chromatic_aberration.dart` (опционально):** R/G/B channel split на focused inputs — light variant. То же API с `force`.
- **Theme-aware auto-gating:** в `build()` каждого эффекта прочитать `Theme.of(context).brightness`. Если `Brightness.light` И `force == false` — вернуть `child` напрямую без overlay (light mode = "less ornate / high contrast", см. 5.1). Это encapsulates правило в widget'е, чтобы call site'ам не приходилось писать `if (brightness == dark)` руками. `force: true` — escape hatch для тестов и редких сценариев где эффект нужен независимо от темы.
- Респект `MediaQuery.disableAnimations` — если эффект имеет анимированную часть (grain shimmer, scanline scroll), статическая версия в этом режиме (нужно для golden tests + accessibility "reduce motion").
- Документировать "Signature elements" в `docs/design-system.md` — какие эффекты, где, как НЕ переборщить, "Effects auto-disable in light mode" — явное правило.
- Логирование: `Logger.debug('[fx:scanline] mount intensity=... brightness=...')`, `[fx:grain] mount opacity=... brightness=...` — раз на mount, чтобы было видно когда widget gated-out.

### 0.6 Document design system stub

- Файл: `docs/design-system.md`.
- Структура: **Aesthetic direction** (0.1) → **Fonts** (с licensing chain из 0.3) → **Token catalogue** (0.4) → **Signature elements** (0.5) → **Performance discipline** (placeholder, заполняется 1.11) → **Component inventory** (placeholder — заполнится в Phase 9.3).
- Markdown-таблицы со значениями токенов; "Anti-patterns" блок (`Theme.of(context).colorScheme` запрещено, bare `AlertDialog` запрещено, system fonts запрещены).
- Логирование: N/A.

## Phase 1 — Foundational reusable widgets

Каждый виджет создаётся в `client/lib/themes/apple_liquid/widgets/` (или подпапке) с публичным API + DartDoc. Все логируют `Logger.debug('[ds:<name>] <event>')` на ключевые события (build, action, dismissal).

### 1.1 `SectionHeader` widget

- Файл: `client/lib/themes/apple_liquid/widgets/section_header.dart`.
- API: `SectionHeader({ required String title, Widget? trailing, EdgeInsetsGeometry? padding })`.
- Использует `AppTypography.title3` и `AppSpacing.screenEdge`.
- Семантика: `Semantics(header: true, label: title)` обёртка вокруг title — обязательно для screen reader'ов.
- Логирование: `Logger.debug('[ds:section-header] title=...')`.

### 1.2 `ListDivider` widget

- Файл: `.../widgets/list_divider.dart`.
- Тонкий divider с `AppColors.dividerSubtle`, indent поддерживается.
- Логирование: N/A.

### 1.3 `StealthHaptics` service

- Файл: `client/lib/themes/apple_liquid/feedback/stealth_haptics.dart`.
- API: `class StealthHaptics { static Future<void> light(); medium(); heavy(); success(); warn(); error(); selection(); }`.
- Обёртка над `HapticFeedback.lightImpact/mediumImpact/heavyImpact/selectionClick` + кастомные паттерны `success` (medium → light) / `warn` (heavy → light) / `error` (heavy × 2 с 80 ms gap).
- Respect `MediaQuery.disableAnimations` / accessibility "reduce motion" — fallback на silent no-op.
- На web — `HapticFeedback.*` no-op'нет в Flutter SDK; задокументировать.
- Wire после 1.4: snackbar auto-haptic по `SnackKind`; dialog destructive — confirm; message send — light; call dial/hangup — medium; theme toggle — selection.
- Логирование: `Logger.info('[haptics] $intensity')`.

### 1.4 `StealthSnackBar` + `showStealthSnackBar` helper

- Файл: `client/lib/themes/apple_liquid/feedback/stealth_snack_bar.dart`.
- API: `enum SnackKind { info, success, warn, danger }`, `void showStealthSnackBar(BuildContext ctx, String message, { SnackKind kind = SnackKind.info, Duration? duration, SnackBarAction? action })`.
- Строит `SnackBar` с `GlassContainer` background, accent-полосой (blue/green/orange/red), `AppTypography.body`, `AppSpacing.radiusLg`.
- **Position above bottom nav:** `behavior: SnackBarBehavior.floating` + `margin = AppSpacing.bottomBarOverlap + AppSpacing.md` чтобы не перекрывать `GlassBottomNavBar`.
- **Auto-haptic** через `StealthHaptics` (из 1.3).
- **Reduce motion:** если `MediaQuery.disableAnimations == true` — fade-only без slide.
- Логирование: `Logger.info('[ds:snack] kind=$kind msg=...')`.

### 1.5 `StealthDialog` + `showStealthDialog` helper

- Файл: `.../feedback/stealth_dialog.dart`.
- API: `Future<T?> showStealthDialog<T>({ required BuildContext ctx, required String title, Widget? body, List<StealthDialogAction>? actions, bool barrierDismissible = true, DialogImportance importance = DialogImportance.normal })`.
- Оболочка — `Dialog` с `GlassContainer(intensity: dark)`, заголовок `AppTypography.headline`, actions — horizontal row `FilledButton`/`TextButton` стандартизированный spacing.
- Variants: `StealthDialogAction.primary/secondary/destructive`. **Destructive 2-tap gate:** первый tap "armed" (showSnackBar "Tap again to confirm"), второй — confirm. Защита от случайного logout/delete/reset.
- **`DialogImportance.high`** (rotate-key, delete-account, factory-reset) — добавляет `ScanlineOverlay` (из 0.5) поверх dialog body.
- Логирование: `Logger.info('[ds:dialog] shown title=...')`, `[ds:dialog] action=...`, `[ds:dialog] destructive armed/confirmed`.

### 1.6 `StealthLoadingIndicator` + `StealthSkeletonTile`

- Файлы: `.../feedback/stealth_loading_indicator.dart`, `.../feedback/stealth_skeleton.dart`.
- `StealthLoadingIndicator` — обёртка над `CircularProgressIndicator` с `AppColors.systemBlue` и фирменным sizing. `StealthLoadingOverlay` — fullscreen variant.
- `StealthSkeletonTile` — шиммер-плейсхолдер; `AppMotion.slow` для shimmer, `AppColors.surfaceMuted` базы.
- Used в chats/contacts loading state вместо bare `CircularProgressIndicator`.
- Логирование: `Logger.debug('[ds:loading] indicator built')`, `[ds:skeleton] mount count=...`.

### 1.7 Refactor `EmptyState` → `StealthEmptyState`

- Файл: `client/lib/ui/widgets/empty_state.dart` (existing).
- Заменить `Theme.of(context).colorScheme` на `AppColors.textSecondary` + `AppColors.surfaceMuted`.
- Расширить API: `StealthEmptyState({ required IconData icon, required String title, String? message, Widget? action })`. Factories `.chats()` и `.contacts()` остаются.
- **Memorable copy + visuals:**
  - Chats empty: *"No conversations yet. Send a contact bundle to start a thread."* + `GrainOverlay` + faint key-fingerprint visual.
  - Contacts empty: *"Your address book is private. Scan a bundle or paste an invite."* + аналогичный fingerprint.
  - Calls empty: *"No calls. Stay silent."*
- Логирование: `Logger.debug('[ds:empty-state] kind=$kind title=...')`.

### 1.8 `GlassPageRoute` custom transition

- Файл: `client/lib/themes/apple_liquid/navigation/glass_page_route.dart`.
- API: `class GlassPageRoute<T> extends PageRoute<T>` — slide-from-right + fade-in, длительность `AppMotion.pageRoute`, кривая `AppMotion.emphasized`.
- Reverse — slide-out-right + fade-out.
- Named ctor `.modal()` — slide-up для priority modals (Phase 7).
- iOS back-swipe: extend `CupertinoPageRoute` на iOS, custom на Android/Web.
- Логирование: `Logger.info('[ds:route] push name=$name')`, `[ds:route] pop name=...`.

### 1.9 `StaggeredListView` wrapper

- Файл: `client/lib/themes/apple_liquid/motion/staggered_list_view.dart`.
- Frontend-design: "one well-orchestrated page load with staggered reveals creates more delight than scattered micro-interactions."
- API: `StaggeredListView.builder({ required int itemCount, required IndexedWidgetBuilder itemBuilder, Duration stagger = const Duration(milliseconds: 40), int maxStaggered = 8 })`.
- Каждый item fade+translate-up на `AppMotion.normal`, delay = `index * stagger`, после `maxStaggered` items — без анимации (cheaper rebuild).
- Respect `MediaQuery.disableAnimations`.
- **Каждый item обёрнут в `RepaintBoundary`** (см. 1.11).
- Used в chats/contacts/profile first render.
- Логирование: `Logger.debug('[ds:stagger] mount itemCount=...')`.

### 1.10 `AccessibilityIds` contract preservation + extension

- Файлы: `client/lib/constants/accessibility_ids.dart`, all screens to be migrated (chats, contacts, profile, settings, call).
- **Контракт:** `accessibility_ids.dart` — "single source of truth for all Semantics wrappers" + завязан на Appium suite ("Do NOT change values"). Существующие 12+ `Semantics()` обёрток MUST переехать verbatim при extraction задачах Phase 2-8.
- **Audit:** `grep -rn "Semantics(" client/lib/` → каталог всех текущих обёрток с label-значением; составить mapping "screen → semantics-set" в задаче.
- **Port verbatim:** при извлечении `ChatTile`, `ContactTile`, `IdentityCard`, и т. д. — обернуть новый widget в `Semantics()` с тем же label из `AccessibilityIds`.
- **Extend:** добавить новые константы для новых widget surface'ов:
  - `chatTileAvatar`, `chatTileLastMessage`, `chatTileUnreadBadge`
  - `contactTileTrailing`, `contactTileVerificationBadge`
  - `sectionHeader`, `listDivider`
  - `snackBarMessage`, `snackBarDismiss`
  - `dialogPrimaryAction`, `dialogSecondaryAction`, `dialogDestructiveAction`
  - `themeToggleSegmented`, `themeToggleLight`, `themeToggleDark`, `themeToggleSystem`
  - `callEncryptedBadge`, `callDurationTimer`, `callConnectionStatus`
- **Appium follow-up:** Appium тест-suite живёт вне репозитория — flag для human follow-up: "after this PR lands, sync `AccessibilityIds` additions with the Appium repo".
- Логирование: при `Semantics` обёртках логирование не нужно — это runtime-зависимая часть.

### 1.11 Performance discipline: `RepaintBoundary` around effects + animations

- Файл: `docs/design-system.md → Performance discipline` (новая секция).
- **Контекст:** `grep RepaintBoundary client/lib` → 0 матчей. `ScanlineOverlay`/`GrainOverlay`/`BackdropFilter` (snack/dialog/glass) + per-item entry animation стекают repaint работы — без боундерей вся subtree выше invalidates каждый кадр.
- **Правила (документировать как non-negotiable):**
  - Каждый эффект-overlay (`ScanlineOverlay`, `GrainOverlay`, `ChromaticAberration`) обёрнут в `RepaintBoundary`.
  - Каждый `StaggeredListView` item обёрнут в `RepaintBoundary`.
  - `StealthLoadingIndicator` / `StealthSkeletonTile` — обёрнут.
  - `GlassChatBubble` — уже анимируется, добавить `RepaintBoundary`.
  - `StealthAnimatedBackground` — уже full-screen анимация, обернуть.
- **Verify:** включить `debugRepaintRainbowEnabled` в debug build один раз и убедиться что эффект-области изолированы от родителей.
- Логирование: N/A (это discipline-rule, не runtime feature).

## Phase 2 — Chats screen redesign

### 2.1 Extract `ChatTile` widget

- Файл: `client/lib/themes/apple_liquid/widgets/chats/chat_tile.dart`.
- `chat`, `lastMessage`, `unreadCount`, `onTap`.
- `AppSpacing.cardPadding`, `AppTypography.body`/`caption1`, `GlassContainer(intensity: ultraLight)`.
- **Preserve `Semantics`:** обернуть в `Semantics(label: '${chat["name"]} ${unreadCount > 0 ? "$unreadCount unread" : ""}', button: true)` — соответствует существующему контракту chat tile.
- Логирование: `Logger.debug('[chats:tile] chatId=...')`.

### 2.2 Migrate `chats_screen.dart` к токенам и новым widgets

- Файл: `client/lib/ui/screens/chats_screen.dart`.
- Inline `EdgeInsets.*` → `AppSpacing.*`; hardcoded colors → `AppColors.*`.
- Loading: `CircularProgressIndicator()` → `StealthSkeletonTile` × N.
- Empty: `EmptyState(type: 'chats')` → `StealthEmptyState.chats()` (grain + fingerprint).
- Separators: inline `SizedBox`/`Divider` → `ListDivider`.
- Все `ScaffoldMessenger` → `showStealthSnackBar`.
- Wrap главный `ListView` в `StaggeredListView` для first-render entrance.
- **`Semantics` audit:** перепроверить что все 2 существующие `Semantics()` обёртки (`chats_screen.dart:713`, `:740`) остались на тех же местах с теми же labels из `AccessibilityIds`.
- Логирование: оставить `[chats]`; `Logger.info('[chats] migrated to design-system v2')`.

### 2.3 Polish `glass_chat_bubble.dart` + mono timestamps + scan-line

- Файл: `client/lib/themes/apple_liquid/widgets/glass_chat_bubble.dart`.
- Tighten padding на `AppSpacing.tileGap`; magic blur σ → `AppEffects`.
- **Mono timestamps:** `AppTypography.captionMono` (новый стиль с monospace font из 0.2).
- **Scan-line на outgoing bubbles:** `ScanlineOverlay(intensity: 0.5)` только на outgoing — signature ownership marker.
- **Micro-pulse на delivery-tick:** `AppMotion.fast` (200 ms scale 1.0→1.15→1.0) когда статус → 'delivered'.
- `AnimatedSize` для appearance, длительность `AppMotion.fast`.
- **Обёрнуть в `RepaintBoundary`** (1.11).
- Логирование: оставить (горячий путь — не логируем per build).

### 2.4 Migrate `glass_message_input.dart` к токенам

- Файл: `.../widgets/glass_message_input.dart`.
- Magic `40` / `36×36` / `8` → `AppSpacing.*`.
- Recording state: pulsing red circle + duration с `AppMotion.normal` + `AppColors.statusDanger`.
- Send tap → `StealthHaptics.light`; record start → `medium`; stop → `light`.
- Логирование: `Logger.debug('[chat-input] recording start/stop')`.

## Phase 3 — Contacts screen redesign

### 3.1 Extract `ContactTile` widget

- Файл: `client/lib/themes/apple_liquid/widgets/contacts/contact_tile.dart`.
- `ContactTile({ required Map<String, dynamic> contact, VoidCallback? onTap, VoidCallback? onCall, Widget? trailing })`.
- Avatar circle (initial-based; цвет из nickname hash → одна из 8-цветной accent палитры), nickname, last-seen.
- **Preserve `Semantics`:** существующий контакт tile имеет 9 `Semantics()` обёрток — порт verbatim с labels из `AccessibilityIds`.
- Логирование: `Logger.debug('[contacts:tile] userId=...')`.

### 3.2 Migrate `contacts_screen.dart` к токенам и новым widgets

- Файл: `client/lib/ui/screens/contacts_screen.dart`.
- Inline `EdgeInsets.only(bottom: 80)` → `AppSpacing.bottomBarOverlap`.
- Контакты → `ContactTile` (3.1).
- Actions bare `showModalBottomSheet` → `StealthDialog` (или новый `StealthActionSheet` — решить в имплементации).
- Snackbars → `showStealthSnackBar`.
- Empty state → `StealthEmptyState.contacts()`.
- Wrap grid в `StaggeredListView`.
- **`Semantics` audit:** все 9 существующих обёрток (`contacts_screen.dart:259, 308, 474, 498, 527, 598, 626` и тд) — sync с `AccessibilityIds` константами.
- Логирование: `Logger.info('[contacts] migrated to design-system v2')`.

### 3.3 Bare `AlertDialog` usage → `StealthDialog`

- Файл: `contacts_screen.dart` + subdialogs.
- Все `showDialog(builder: (_) => AlertDialog(...))` → `showStealthDialog(...)`.
- Delete-contact → destructive 2-tap + `DialogImportance.high` (scan-line).
- Логирование: покрывается `[ds:dialog]`.

## Phase 4 — Profile screen redesign

### 4.1 Extract 5 cards + asymmetric grid layout

- Папка: `client/lib/themes/apple_liquid/widgets/profile/`.
- Files: `identity_card.dart`, `security_card.dart`, `activity_card.dart`, `storage_card.dart`, `call_history_card.dart`.
- Каждая принимает данные через конструктор (нет прямого доступа к `LocalAppService`).
- **Asymmetric grid** (frontend-design "grid-breaking elements"):
  - `IdentityCard` (QR + user-id + safety-number-hint) — full-width hero card сверху, height ~280 px.
  - `SecurityCard` + `ActivityCard` — side-by-side 2-column row (Flex 1:1).
  - `StorageCard` — full-width.
  - `CallHistoryCard` — full-width, последняя.
- `GlassContainer(intensity: light)`, `SectionHeader` внутри (где уместно), `AppSpacing.cardPadding`.
- **Preserve `Semantics`:** `AccessibilityIds.userId` / `username` / `copyContactBundle` / `logout` — порт verbatim.
- Логирование: `Logger.debug('[profile:card] name=...')`.

### 4.2 Migrate `profile_screen.dart` к токенам и helpers

- Файл: `client/lib/ui/screens/profile_screen.dart`.
- `_buildIdentityCard()` локальные функции → импорт из 4.1.
- `Stack` + `Positioned(bottom: 100)` для logout FAB → `Scaffold.floatingActionButton` + `FloatingActionButtonLocation.endFloat`.
- Hardcoded `SizedBox(height: 80)` → `AppSpacing.bottomBarOverlap`.
- Loading → `StealthLoadingIndicator`.
- Error/empty ("Unable to load profile") → `StealthEmptyState` с retry action.
- Snackbars → `showStealthSnackBar(kind: SnackKind.success)`.
- Wrap card list в `StaggeredListView`.
- Логирование: `Logger.info('[profile] migrated to design-system v2')`.

### 4.3 Replace bare dialogs in profile flow

- Logout confirmation → `showStealthDialog(action: destructive)` + 2-tap gate + `DialogImportance.high`.
- Логирование: покрывается `[ds:dialog]`.

## Phase 5 — Settings screen + dark-first commitment

### 5.1 Dark-first hierarchy commitment (with backward-compat gate)

- Файлы: `client/lib/main.dart` (default-mode logic), `client/lib/themes/apple_liquid/liquid_theme.dart` (только contrast tweaks если WCAG нужно), `docs/design-system.md` (dual-identity doc + список widget'ов которые gate'ятся на brightness).
- Frontend-design: Stealth — фундаментально dark aesthetic. Commit это явно.
- **Backward-compat gate:** только для FRESH installs менять default. Логика:

  ```dart
  final prefs = await SharedPreferences.getInstance();
  final hasPersisted = prefs.containsKey('themeMode');
  final defaultMode = hasPersisted ? ... : ThemeMode.dark;
  ```

  Если у юзера уже был persisted preference (включая `ThemeMode.system`) — уважать его. Только новый install получает dark default. Избегает surprise switch при обновлении.
- **Где живёт "less ornate" в light mode (важно — это НЕ в `liquid_theme.dart`):**
  - `liquid_theme.dart` хранит только `ThemeData` (colors, text styles). "Ornament" не существует на уровне ThemeData — он в WIDGETS, которые читают `Theme.of(context).brightness`.
  - **Touchpoints:**
    - `ScanlineOverlay` / `GrainOverlay` / `ChromaticAberration` (из 0.5) — auto-disable в light (theme-aware gating).
    - `GlassContainer` — в light brightness использует lower-intensity preset (`ultraLight` вместо `light`, `light` вместо `medium`, и т.д.). Реализуется в `GlassContainer.build` через `Theme.of(context).brightness` lookup, не через изменение `GlassStyles` пресетов.
    - `GlassChatBubble` — outgoing-message scan-line (из 2.3) — пропускается в light (унаследовано из `ScanlineOverlay` auto-gating).
    - `StealthAnimatedBackground` — в light: статичный градиент без анимации (animated blur spots отключены).
  - `liquid_theme.dart` правки: только тонкая настройка контраста — `colorScheme` для light увеличивает text-on-background contrast, если WCAG AA fail'ит в текущей конфигурации.
- Документировать dual identity в `docs/design-system.md → Dual identity` с явной таблицей "Widget × Behavior in dark / Behavior in light".
- Логирование: `Logger.info('[theme] default=$defaultMode resolved=$mode persistedPref=$hasPersisted')`.

### 5.2 Group settings в SectionHeader-led groups

- Файл: `client/lib/ui/screens/settings_screen.dart`.
- Группы: "Appearance", "Connection", "Privacy", "Storage", "Developer".
- Каждая: `SectionHeader(title: ...)` + `GlassContainer(intensity: ultraLight)` с rows.
- Row pattern: leading icon + title + optional subtitle + trailing (`Switch`, `Text`, chevron).
- Логирование: `Logger.debug('[settings:row] tap key=...')`.

### 5.3 Theme mode toggle (dark-biased)

- Файл: тот же.
- UI: `SegmentedButton<ThemeMode>` с тремя options.
- **Dark-biased presentation:** dark — primary highlighted state; light label = "Accessibility / High contrast"; system label = "Match OS".
- Без Riverpod — `ValueNotifier<ThemeMode>` в `main.dart`, прокидывается в `SettingsScreen` через constructor. При merge с hardening → `themeModeProvider`.
- Persist в `SharedPreferences['themeMode']`.
- `StealthHaptics.selection` на toggle change.
- **`Semantics`:** новые IDs `themeToggleSegmented`, `themeToggleLight/Dark/System` (из 1.10).
- Логирование: `Logger.info('[settings:theme] mode=$mode source=user-toggle')`.

### 5.4 Migrate snackbar/dialog usages в `settings_screen.dart`

- Все `ScaffoldMessenger` → `showStealthSnackBar`.
- "Reset all data" → `showStealthDialog(action: destructive, importance: high)`.
- Логирование: покрыто helper'ами.

## Phase 6 — Startup flow polish (loading / registration / error)

### 6.1 Polish `loading_screen.dart`

- Файл: `client/lib/loading_screen.dart`.
- Decision: оставить `CircuitBoardBackground` как deliberate first-touch visual; через 400 ms crossfade на `StealthAnimatedBackground` через `AnimatedSwitcher`/`AnimatedOpacity`.
- Card → `GlassContainer(intensity: medium)`.
- `LinearProgressIndicator` → `AppColors.systemBlue` + `AppSpacing.radiusXs`.
- Text → `AppTypography.body`; secondary → `AppTypography.caption1` в `AppColors.textSecondary`.
- Логирование: `Logger.info('[loading] step $index/$total')`.

### 6.2 Polish `registration_screen.dart`

- Файл: `client/lib/registration_screen.dart`.
- Hero block top; privacy pitch — `AppTypography.body` + `AppColors.textSecondary`.
- "GET STARTED" → `FilledButton` `AppSpacing.buttonHeight` + `radiusLg`.
- Validation errors → `showStealthSnackBar(kind: SnackKind.danger)`.
- Loading → `StealthLoadingIndicator`.
- Submit success → `StealthHaptics.success`.
- Background: `GrainOverlay` (из 0.5).
- Логирование: `Logger.info('[registration] form submit nickname.length=...')`.

### 6.3 Verify + polish `startup_error_screen.dart`

- Файл: `client/lib/ui/screens/startup_error_screen.dart`.
- Уже использует `StealthAnimatedBackground` + AppColors + AppSpacing per recon — проверить совместимость с Phase 0 token-аудитом.
- Retry CTA → `FilledButton`.
- Add `Logger.error('[startup-error] shown msg=...')`.

## Phase 7 — WebRTC call screens redesign

### 7.1 Extract shared `CallHudOverlay` + polish `webrtc_call_screen_native_impl.dart`

- Файлы: `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart` (новый, shared), `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`.
- **Extract `CallHudOverlay` first** (shared widget, не зависит от платформенных WebRTC bindings) — этим виджетом пользуются и native, и web (7.2).
- `CallHudOverlay` содержит:
  - Duration timer — large monospace `AppTypography.titleMono` (из 0.2). Чёткий технический look.
  - Connection-quality `StatusChip` (из 8.2) — "EXCELLENT / GOOD / DEGRADED / RECONNECTING".
  - Animated **"E2E ENCRYPTED"** badge — pulsing blue glow + subtle `ScanlineOverlay`. Signature security moment.
- Extract `CallControlButtons` widget (mute, speaker, hangup) → `.../widgets/call/call_control_buttons.dart`. Circular glass buttons; hangup `AppColors.statusDanger`; mute/speaker `AppColors.glassMedium`.
- `webrtc_call_screen_native_impl.dart` использует `CallHudOverlay` + `CallControlButtons`. Status positioning: `SafeArea` + `AppSpacing.screenEdge`.
- Button taps: `StealthHaptics.medium` mute/speaker, `heavy` hangup, `error` connection loss.
- **Preserve `Semantics`:** `AccessibilityIds.hangUp/mute/speaker/callStatus/callerName` — порт verbatim. Добавить новые: `callEncryptedBadge`, `callDurationTimer`, `callConnectionStatus`.
- Логирование: оставить `[stealth-call]`; `Logger.info('[call:hud] connection-quality=$q')`.

### 7.2 Polish `webrtc_call_screen_web.dart`

- Файл: `client/lib/ui/screens/webrtc_call_screen_web.dart`.
- Use shared `CallHudOverlay` + `CallControlButtons` из 7.1 — identical look.
- Логирование: оставить.

### 7.3 Custom page-route для call screen

- Сменить `MaterialPageRoute` → `GlassPageRoute.modal()` (slide-up, `AppMotion.pageRoute`).
- Pop transition — slide-down + fade.
- Edit points: каждый `Navigator.push(MaterialPageRoute(... WebRTCCallScreen ...))`.
- Логирование: покрывается `[ds:route]`.

## Phase 8 — WebRTC diagnostics screens

### 8.1 Restructure `webrtc_diagnostics_screen.dart` (native + web)

- Файлы: `webrtc_diagnostics_screen_native_impl.dart`, `webrtc_diagnostics_screen_web.dart`.
- Группировать checks через `SectionHeader` ("Network", "Codecs", "Permissions").
- Hardcoded `Duration(seconds: 3)` → именованная константа в файле с комментарием.
- Логирование: оставить.

### 8.2 Styled `StatusChip` widget

- Файл: `client/lib/themes/apple_liquid/widgets/status_chip.dart`.
- API: `StatusChip({ required String label, required StatusKind kind })` где `StatusKind { pending, success, warn, danger }`.
- Pill-style с цветом из `AppColors.status*`, `AppTypography.caption1`.
- Used в diagnostics + Phase 7 (connection quality).
- Логирование: `Logger.debug('[ds:status-chip] kind=...')`.

## Phase 9 — Golden-test infra + tests + docs + visual reel

### 9.0 Setup golden-test infrastructure

- **Блокирующая prerequisite для 9.5.**
- Файлы: `client/pubspec.yaml` (devDependencies), `client/test/helpers/golden_config.dart` (новый), `client/test/helpers/animation_freeze.dart` (новый, см. ниже), `client/test/golden/` (новая папка), CI workflow (если есть, например `.github/workflows/`).
- **Decision points (при старте задачи):**
  - Built-in `flutter_test` matchesGoldenFile vs `golden_toolkit` package. Рекомендую `golden_toolkit` — он решает font loading для CI (Skia на CI грузит fallback'и, не наши custom шрифты), multi-device size variants out of the box.
  - Font loading в тестах: `golden_toolkit` `loadAppFonts()` — pre-load всех `pubspec.yaml` font files перед запуском goldens. Иначе snapshots будут отличаться dev vs CI.
- **Setup:**
  - Add `golden_toolkit: ^0.15.0` (или последнюю) в devDependencies.
  - `client/test/helpers/golden_config.dart` — boilerplate (`testGoldens`, `loadAppFonts`, device frame configs для phone/tablet).
  - Создать `client/test/golden/` директорию + `.gitattributes` для PNG diff handling.
  - `flutter_test_config.dart` — global setup для всех тестов (auto-load fonts).
  - CI step: `flutter test --tags golden` или dedicated job, с `--update-goldens` запретом на main (только manual).
- **CRITICAL — animation freeze rule for goldens:**
  - `grep AnimationController client/lib/themes/apple_liquid` → continuous animations: `StealthAnimatedBackground` (20-sec loop), `GlassContainer` (own controller), `GlassChatBubble` (`AnimatedSize`), future `StaggeredListView` / `GrainOverlay` (если animated). `tester.pumpAndSettle()` будет deadlock'ить ожидая когда continuous animation закончится → тесты hang / timeout flakily.
  - Helper в `client/test/helpers/animation_freeze.dart`:

    ```dart
    Future<void> pumpForGolden(WidgetTester tester, Widget widget) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: widget,
        ),
      );
      // Use pumpFrames with a small budget instead of pumpAndSettle
      // to avoid deadlocking on continuous animations.
      await tester.pumpFrames(widget, const Duration(milliseconds: 100));
    }
    ```

  - **Все golden tests в 9.5 MUST использовать `pumpForGolden`, не `pumpAndSettle`.** Документировать в `client/test/helpers/golden_config.dart` header.
  - **Все animated widgets MUST respect `MediaQuery.disableAnimations`:**
    - `StealthAnimatedBackground` — статичный градиент при `disableAnimations`.
    - `GlassContainer` — пропустить animated entrance.
    - `StaggeredListView` (1.9) — уже описано в задаче.
    - `GrainOverlay` / `ScanlineOverlay` — если animated (shimmer/scroll), use static variant.
    - `StealthSnackBar` (1.4) / `StealthDialog` (1.5) / `GlassPageRoute` (1.8) — уже описано в задачах.
  - Без этого правила: snapshot'ы либо deadlock'нут, либо randomly capture'нутся на разных кадрах анимации → meaningless diffs.
- **Verify locally:** запустить `flutter test --update-goldens` один раз — проверить что snapshot'ы генерируются стабильно (запустить второй раз — diff должен быть пуст).
- Логирование: N/A (test infra).

### 9.1 Widget-тесты для дизайн-системы (Phase 1)

- Файлы: `client/test/themes/apple_liquid/widgets/`.
- Тесты:
  - `section_header_test.dart` — title + trailing, правильный typography, `Semantics(header: true)` присутствует.
  - `stealth_snack_bar_test.dart` — показывается, kind влияет на accent, dismiss работает, auto-haptic через mock `StealthHaptics`. Тест с `MediaQuery(disableAnimations: true)` — slide отключается.
  - `stealth_dialog_test.dart` — actions tappable, destructive 2-tap gate (first arms via snackbar, second confirms), `DialogImportance.high` mount'ит `ScanlineOverlay`.
  - `stealth_empty_state_test.dart` — render icon+title+action; callback вызывается.
  - `stealth_haptics_test.dart` — `StealthHaptics.success` → 2 system channel calls (`mediumImpact` + `lightImpact`); `disableAnimations` → silent no-op.
  - `glass_page_route_test.dart` — push/pop transition завершается за `AppMotion.pageRoute`.
  - `staggered_list_view_test.dart` — items появляются с правильным delay; после `maxStaggered` — без анимации; `RepaintBoundary` присутствует.

### 9.2 Regression smoke-tests для мигрируемых экранов

- Файлы: `client/test/widgets/chats_screen_design_test.dart` (extend), `contacts_screen_design_test.dart`, `profile_screen_design_test.dart`, `settings_screen_design_test.dart`.
- Smoke: каждый экран mount'ится с фейковым data source / LocalAppService override; асёрты на наличие хотя бы одного `SectionHeader` ИЛИ ключевого нового widget (`ChatTile`, `ContactTile`, `IdentityCard`).
- **Semantics regression:** для каждого мигрируемого экрана — `testWidgets` который проверяет presence всех existing `AccessibilityIds.*` labels в `WidgetTester`. Если миграция дропнула label — тест падает с понятным сообщением.
- Profile test: проверить asymmetric grid (`IdentityCard` full-width, `SecurityCard`+`ActivityCard` 2-col Row).
- Settings test: theme toggle отображается и переключает `ValueNotifier<ThemeMode>`.

### 9.3 `docs/design-system.md` — финальная версия

- Файл: `docs/design-system.md`.
- Финальные token-таблицы, **aesthetic direction** statement, signature elements gallery, component inventory с примерами usage, **dual identity** (dark = signature, light = high-contrast), **Performance discipline** (из 1.11), **Accessibility contract** (links на `AccessibilityIds`), **Fonts → Licensing & budgets**.
- "Migration cheatsheet": `EdgeInsets.all(16)` → `AppSpacing.md`; bare `AlertDialog` → `StealthDialog`; etc.
- "Anti-patterns": `Theme.of(context).colorScheme`, bare `ScaffoldMessenger`, system fonts, missing `RepaintBoundary` в overlay widget'ах.

### 9.4 Refresh `docs/ARCHITECTURE.md` UI-секции

- Файл: `docs/ARCHITECTURE.md`.
- Упомянуть design-system в архитектурной диаграмме; описать, что все экраны зависят от `apple_liquid/` design layer.
- Link на `docs/design-system.md`.

### 9.5 Golden-test visual reel

- Файлы: `client/test/golden/<screen>_<theme>.png` (auto-generated).
- Используя инфру из 9.0 — golden-test'ы для key screens в обоих темах:
  - Chats list (light + dark), пустой и с 3 чатами.
  - Profile screen (light + dark) с asymmetric grid.
  - Settings screen (light + dark).
  - Registration screen.
  - Loading screen (mid-crossfade).
  - In-call HUD (с E2E ENCRYPTED badge).
  - Empty states (chats / contacts).
- Каждый тест устанавливает фиксированный device size (например `Device.phone` + `Device.tabletPortrait`) и фиксированный seed для random элементов (avatar color).
- `flutter test --update-goldens` baseline commit'ится в `client/test/golden/`. PR CI'ы запускают `flutter test` (без update) — diff'ы блокируют merge.
- Update `docs/design-system.md → Component gallery` с link'ами на эти изображения.

## Commit plan

Девять чекпоинтов. Каждый коммит green (`flutter analyze` clean, `flutter test` green) перед переходом к следующей фазе.

| # | Phase | Subtasks | Conventional commit subject |
|---|-------|---------:|-----------------------------|
| C1 | Phase 0 | 6 | `chore(design): commit aesthetic direction; verify fonts; add tokens + signature effects` |
| C2 | Phase 1 | 11 | `feat(ui): design-system primitives (haptics/snack/dialog/route/stagger/section) + a11y + perf rules` |
| C3 | Phase 2 | 4 | `refactor(ui): chats screen migrated to design-system v2 + mono timestamps + scan-line` |
| C4 | Phase 3 | 3 | `refactor(ui): contacts screen migrated to design-system v2` |
| C5 | Phase 4 | 3 | `refactor(ui): profile screen — asymmetric card grid + helpers` |
| C6 | Phase 5 | 4 | `feat(ui): settings screen + dark-first commitment + explicit theme toggle` |
| C7 | Phase 6 | 3 | `refactor(ui): loading / registration / startup-error polish` |
| C8 | Phase 7+8 | 5 | `refactor(ui): WebRTC call HUD (shared) + diagnostics screens redesign` |
| C9 | Phase 9 | 6 | `test+docs(ui): golden infra; cover design-system widgets; visual reel; document tokens` |

**Total tasks:** 45. **Total commits:** 9.

## Открытые вопросы / решения по умолчанию

1. **Aesthetic direction:** рекомендуется **Refined crypto-noir**. Выбор фиксируется в 0.1.
2. **Font pair (зависит от 0.1):** при crypto-noir — **Geist Mono + Geist Sans** (OFL/MIT, free, verified). Если licensing/aesthetics зашевелит — альтернатива в OFL-пуле.
3. **Font budget:** ≤ +600 KB web bundle, ≤ +1.5 MB mobile. Subset обязателен. Если превышено — drop italics/light/black weights.
4. **Custom icon set vs Material Icons:** Material остаётся; кастомный set — отдельная задача после Phase 9 если визуальный пробел очевиден.
5. **CircuitBoardBackground vs StealthAnimatedBackground в LoadingScreen:** crossfade (6.1).
6. **Theme toggle wiring без Riverpod:** `ValueNotifier<ThemeMode>` (5.3). При merge с hardening → `themeModeProvider`.
7. **Dark-first для existing users:** backward-compat gate (5.1) — только fresh installs получают dark default.
8. **iOS back-swipe:** `GlassPageRoute` extend'ит `CupertinoPageRoute` на iOS.
9. **Goldens (9.0/9.5):** `golden_toolkit` package + pre-load fonts. CI блокирует на golden diff'ах.
10. **AccessibilityIds (1.10):** Appium suite вне репо — flag для human follow-up при merge'е PR.
11. **`RepaintBoundary` discipline (1.11):** non-negotiable правило для всех новых overlay/animation widget'ов.
12. **Конфликт с hardening branch:** все widgets additive; mergeable, не trivial — safety-number и rotation UI потребуют пересборки поверх `StealthDialog`/`SectionHeader`.
13. **Haptics на web:** silently no-op'нет в Flutter SDK. Документировано.
14. **Web performance:** добавление `BackdropFilter` в snack/dialog + signature effects может degrade web performance — `RepaintBoundary` discipline + golden snapshots помогут отловить регрессии.
