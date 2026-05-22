# Plan: Diagnostics & Logs Screen

**Branch:** `feature/diagnostics-logs-screen`
**Created:** 2026-05-22
**Refined:** 2026-05-22 (`/aif-improve` × 5 passes)
**Author:** anikakle
**Mode:** full (no `--parallel`)

## Цель

Добавить in-app экран **Диагностика**, который показывает:

1. последние ERROR/WARN записи из локального логгера (in-memory ring-buffer);
2. живые статусы 5 ключевых сервисов (БД, attachments, identity, P2P, PocketBase config);
3. кнопку «Share logs» — одним нажатием формирует текстовый отчёт и отдаёт его в системный share-sheet (Telegram, Signal, mail) с обязательным inline scrubber'ом sensitive ids.

**UI strings — на английском** для consistency с существующими экранами (settings_screen использует 'Settings', 'Privacy & security' и т.п.). `language.ui: ru` в config.yaml управляет prompts, не in-app strings.

Цель — упростить дебаг и крауд-репорты от пользователей без `adb logcat` / Safari Web Inspector.

## Settings

- **Testing:** yes (unit на buffer / scrubber / service / composer + widget-тест на экран)
- **Logging:** verbose. **Правильная сигнатура — `Logger.debug(message, extras: {...})`**; никаких tag-аргументов (см. `client/lib/logging/logger.dart:110`).
- **Docs:** yes — обязательный docs checkpoint в конце; `/aif-implement` обязан прогнать `/aif-docs` перед завершением

## Roadmap Linkage

- **Milestone:** none
- **Rationale:** Skipped by user. Кандидат на новый M17 — отдельное решение `/aif-roadmap` после merge.

## Research Context

См. `.ai-factory/RESEARCH.md` Active Summary — он сейчас посвящён Double Ratchet (M15) и к этому плану отношения не имеет.

## Контекст из глубокой разведки (`/aif-improve` × 2)

### Pass 1 (API ландшафт)
- **Logger API:** `Logger.{debug,info,warn,error}(String message, {Map<String,dynamic>? extras})`. Redaction работает ТОЛЬКО для значений в `extras` с ключами из `_sensitiveKeys` (`logger.dart:24`). `redactId(String?)` — top-level, редактирует значение **целиком**, не ищет UUID inside text. Для экспорта нужен **отдельный inline-pattern scrubber** (Task 16).
- **`Logger.redact()` не существует** — везде заменено в плане.
- **Allow-list `no_bare_logging_test.dart`** покрывает только `lib/logging/logger.dart`. Новый `lib/logging/log_buffer.dart` не пишет в `debugPrint` → расширять allow-list не нужно.
- **`GlassPageRoute` отсутствует** — везде `MaterialPageRoute`.
- **Existing share fallback** — `Clipboard.setData` уже используется в `profile_screen.dart` и `webrtc_diagnostics_screen_web.dart`.
- **Existing `webrtc_diagnostics_screen`** — conditional-export (`_stub`/`_io`/`_web`/`_native_impl`). Не трогаем; параллельная фича.
- **Pubspec.lock в git** — одна правка pubspec + один `flutter pub get` (Task 15).

### Pass 5 (lifecycle ownership и структура LogEntry)
- **Lifecycle утечка `DiagnosticsService` через `LocalAppService` ownership.** `LocalAppService` создаётся в state виджета (`settings_screen.dart:24`); каждое открытие SettingsScreen создаёт новый инстанс + новый `Timer.periodic` без dispose. **Решение:** `LocalAppService.createDiagnostics()` — **factory method**, не геттер. `DiagnosticsScreen` сам владеет lifecycle: создаёт инстанс через `diagnosticsFactory` в `initState`, зовёт `dispose()` в state.dispose(). Timer.periodic привязан к жизни screen, а не приложения. `LocalAppService.logout()` НЕ трогает diagnostics (он его не владеет — уточнение Pass 3 отменено).
- **`LogEntry` структурированный для UI.** План раньше предполагал `formattedLine: String` (готовая строка с level prefix). UI tile должен рендерить level badge / timestamp / message раздельно — парсить formattedLine обратно хрупко. **Решение:** хранить структурированно — `level`, `timestampUtc`, `message` (без prefix), `extrasText` (nullable suffix). Геттер `formattedLine` собирает финальную строку для composer'а (Task 5). UI tile использует поля напрямую.

### Pass 4 (testability — provider injection)
- **Concrete services не моккаются:** `DashboardService`, `AttachmentService`, `IdentityService` имеют конструкторы без параметров и создают `_localDb`/`_storage` внутри; `P2PService.instance` — singleton. В unit-тесте подменить их нельзя без рефакторинга всего проекта. **Решение:** `DiagnosticsService` принимает **provider functions** (closures), не сами сервисы. Production wiring передаёт method tear-offs; тест передаёт fake closures. Это локальный фикс, нулевая инвазивность.
- **`Logger.snapshot()` — global static**, в widget-тесте экрана подменить нельзя (накопит шум от других тестов в suite). `DiagnosticsScreen` принимает опциональный `logProvider` параметр с default `Logger.snapshot` (tear-off). В тесте передаётся fake provider с фиксированным списком.
- **`ShareInvoker` typedef** определяется в `diagnostics_share.dart` (Task 8) как `Future<ShareOutcome> Function(BuildContext, String)`. Top-level `shareDiagnosticsReport` совместима с этой сигнатурой — используется как default value параметра `DiagnosticsScreen.shareInvoker`. Никаких extra abstract classes.
- **Re-entrance защита в DiagnosticsService:** `_collectInProgress` mutex чтобы новый periodic tick не запускал параллельный `Future.wait` если предыдущий завис на медленном БД-вызове.

### Pass 3 (lifecycle и UI consistency)
- **`WebRtcSignalingService` per-call, не singleton** — создаётся в `native_call_controller.dart:42`, `p2p_service.dart:150`, `web_call_controller.dart:36` и уничтожается с концом звонка/P2P. Постоянной reference не получить. Источник `signaling` **убран** — health-источников осталось **5**. Realtime SSE state — отдельный план (требует публичного API в `IncomingCallSignalingService` + проброса через `CallManager`, gold-plating для первого мерджа).
- **`StreamController.broadcast()` не replay'ит** последнее значение новому listener'у — UI висел бы на loading 5 секунд до первого `Timer.periodic` tick. Решение: `DiagnosticsService.lastKnownSnapshot` cache + `onListen` callback в broadcast-контроллере + `StreamBuilder(initialData: ...)` в UI.
- **In-app UI текст на английском** — `settings_screen.dart:140` `GlassAppBar(title: 'Settings')`, плюс все labels ('Privacy & security', 'Open WebRTC diagnostics', 'Sign out') на английском. Новый UI ('Diagnostics & logs', 'Share logs', 'No log entries yet', 'Copied to clipboard') — тоже английский.
- **share_plus 10.x может требовать Dart 3.3+**; текущий pubspec.yaml: `sdk: '>=3.0.0 <4.0.0'`. Task 15: при failure bump SDK constraint ИЛИ pin share_plus к 7.x. Android: `share_plus 10` обычно auto-merge'ит FileProvider, но при `SecurityException` нужна ручная регистрация в AndroidManifest.xml. iOS — out of box.
- **GlassButton принимает `child`, не `icon`/`label`** (`themes/apple_liquid/components/glass_container.dart:117`). Для кнопки с иконкой и текстом — `Row(children: [Icon(...), SizedBox(width: 8), Text(...)])` как child.
- **Tmp-file cleanup** — Task 8 удаляет старые `stealth-diagnostics-*.txt` перед записью нового, избегая unbounded disk usage.

### Pass 2 (фактические сигнатуры — три галлюцинации устранены)
- **`GroupSecretService.knownGroupIds()` не существует** (`group_secret_service.dart` экспонирует только `resolve`/`encryptForGroup`/`decryptForGroup`/`clearOnLogout`; `_cache` private). Источник `group_secrets` **убран** — health-источников теперь **6**, не 7.
- **`DashboardService.getDashboardSummary()`** возвращает `bucketReady: true` и `localMediaReady: true` **hardcoded** (`dashboard_service.dart:31–39`). Единственный реальный сигнал — `secureStorageReady`. Источник `database` использует ТОЛЬКО его.
- **`AttachmentService.getStorageDebugSummary()`** аналогично hardcoded `bucketReady: true`; реальный сигнал — `fileCount` (int). Bytes недоступны.
- **`PocketBaseClient.instance` бросает `StateError`** на пустом `POCKETBASE_URL` (`pocketbase_client.dart:30`). И `AppEnvironmentInfo`, и `DiagnosticsService` источник `pocketbase` читают `dotenv.env['POCKETBASE_URL']` **напрямую**, минуя singleton, чтобы не уронить collect/snapshot.
- **`P2PService` без публичного status API** — `_signalingSubs` и retry-worker state private. Task 17 добавляет публичные геттеры `activeChannelCount` + `retryWorkerRunning`. Без него health-источник `p2p` собрать нельзя.
- **`LocalAppService.logout()`** должен дополнительно вызывать `_diagnostics.dispose()`, иначе 5-сек таймер и signaling-подписка остаются висеть после logout.
- **Perf-контракт UI:** `Logger.snapshot()` НЕ читается на каждом `build()` — кешируется в state экрана, обновляется только на смену filter / refresh-кнопку / опциональный live-таймер.
- **CI Supabase-guard** — `.github/workflows/ci.yml:45` запрещает упоминания `supabase`/`Supabase` в `client/` и `pw-test/`. Учесть в docs (не использовать слово как пример провайдера).

## Tasks

### Phase 0 — Build dependencies & API surface

- [x] **Task 15** — `client/pubspec.yaml`: добавить `package_info_plus: ^8.0.0` и `share_plus: ^10.0.0` + `flutter pub get` + закоммитить lockfile. **Если `flutter pub get` падает по SDK constraint** (`pubspec.yaml:22` — `'>=3.0.0 <4.0.0'`) — bump до `'>=3.3.0 <4.0.0'` ИЛИ pin `share_plus: ^7.2.2`. Manual Android verify (после Task 8): проверить отсутствие `FileUriExposedException` в `flutter logs`; при необходимости добавить FileProvider в AndroidManifest.xml. **Prerequisite для Task 6 и Task 8.**
- [x] **Task 17** — `client/lib/p2p_service.dart`: публичные read-only геттеры `int get activeChannelCount` и `bool get retryWorkerRunning` (приватный флаг `_retryWorkerStarted` ставится в `true` внутри `startRetryWorker()` после успешного init). **Prerequisite для Task 3.**

### Phase 1 — Logging buffer

- [x] **Task 1** — `client/lib/logging/logger.dart` (+ опц. `log_buffer.dart`): in-memory ring-buffer на 500 записей. **`LogEntry`** хранит структурированно — `level`, `timestampUtc`, `message` (без level prefix), `extrasText` (nullable suffix); геттер `formattedLine` собирает строку для composer (см. M2 Pass 5). `Logger.snapshot({min: LogLevel.warn, int? limit})`. Buffer пишет ДО early-return по `currentLevel` — WARN/ERROR попадают в snapshot независимо от console verbosity. Публичный API `Logger.{debug,info,warn,error}` НЕ меняется.
- [x] **Task 2** — `client/test/logging/log_buffer_test.dart`: capacity, FIFO-вытеснение, level-фильтр, limit, независимость от `STEALTH_LOG_LEVEL`.

### Phase 2 — Service status & secure report composer

- [x] **Task 16** — `client/lib/services/diagnostics/log_scrubber.dart` + test: `String scrubInlineSensitive(String)`. Regex для UUID v4 / 15-char PB id (с heuristic против обычных слов) / base64 ed25519/X25519 pub keys. Идемпотентна. **Prerequisite для Task 5.**
- [x] **Task 3** — `client/lib/services/diagnostics/{diagnostics_service.dart, service_status.dart}`: агрегатор **5 источников**. **Конструктор принимает provider functions** (`dashboardSummary`, `attachmentDebugSummary`, `getUserId`, `p2pActiveChannelCount`, `p2pRetryWorkerRunning`, `pocketbaseUrl`), НЕ сами сервисы (см. L1 Pass 4 — критично для testability). `lastKnownSnapshot` cache + `Stream<List<ServiceStatus>> watch()` (`onListen` callback + 5-сек `Timer.periodic`) + `Future<List<ServiceStatus>> snapshot()` (через `Future.wait`) + `_collectInProgress` mutex + `dispose()`. Каждый источник изолирован (exception → state=error локально). _Blocked by Task 17._
- [x] **Task 4** — `client/test/services/diagnostics/diagnostics_service_test.dart`: тестирует через fake provider closures в ctor — никакой подмены real сервисов не нужно. Кейсы: все 5 источников, database `secureStorageReady=false`→error, attachments throws→error локально, pocketbase: null/пустой→error, p2p `retryWorkerRunning=false`→warn, watch эмитит **на onListen** + на periodic tick, `lastKnownSnapshot` обновляется, dispose останавливает таймер (через `fake_async`), re-entrance guard (медленный provider не запускает параллельный сбор).
- [x] **Task 5** — `client/lib/services/diagnostics/diagnostics_report.dart`: `String buildDiagnosticsReport({statuses, logs, env})`. **Каждая строка лога проходит через `scrubInlineSensitive` (Task 16)** перед сборкой; `redactId` не используется для message. Детерминированный порядок (statuses by id, logs by time desc). _Blocked by Task 16._
- [x] **Task 6** — `client/lib/services/diagnostics/app_environment_info.dart`: `AppEnvironmentInfo.collect()` (через `package_info_plus`). `logLevel` из `Logger.currentLevel.name`. `pocketbaseHost` читается из `dotenv.env['POCKETBASE_URL']` напрямую (не через singleton — он бросает на пустом env); пустой/невалидный → `null`. _Blocked by Task 15._
- [x] **Task 7** — `client/test/services/diagnostics/diagnostics_report_test.dart`: golden text inline, проверка inline-scrub UUID, пустой массив логов → `(none)`.

### Phase 3 — Share integration

- [x] **Task 8** — `client/lib/services/diagnostics/diagnostics_share.dart`: `ShareInvoker` typedef + top-level `shareDiagnosticsReport(ctx, text) → Future<ShareOutcome>` (совместимая с typedef для использования как default value в Task 9). Tmp `.txt` → `Share.shareXFiles` → web fallback `Share.share` (без файла, `path_provider` на web не работает) → последний fallback `Clipboard.setData` + SnackBar 'Copied to clipboard'. Tmp-cleanup перед записью. Verbose-логирование. _Blocked by Task 15._

### Phase 4 — UI

- [x] **Task 9** — `client/lib/ui/screens/diagnostics/diagnostics_screen.dart` + 3 widget-файла. `GlassAppBar(title: 'Diagnostics & logs')` + секция 'Services' (`StreamBuilder` с `initialData: _diagnostics.lastKnownSnapshot`) + секция 'Recent logs' (filter chips + `ListView.builder` рендерит `LogEntryTile` на структурированных полях LogEntry) + нижняя `GlassButton`. **UI strings — английский.** **Lifecycle ownership (M1 Pass 5):** ctor принимает `diagnostics` ИЛИ `diagnosticsFactory` (assert: один из двух обязателен). Если factory — state в `initState` создаёт инстанс, в `dispose()` зовёт `dispose()` (per-screen ownership). Если concrete — caller владеет (тесты). Ctor с inject-able `logProvider` (default `Logger.snapshot`) и `shareInvoker` (default `shareDiagnosticsReport`). **Performance contract:** snapshot кешируется в state, обновляется только на filter/refresh/опц. периодик. _Blocked by Task 1, Task 3, Task 5, Task 8._
- [x] **Task 10** — `client/test/ui/screens/diagnostics/diagnostics_screen_test.dart`: тестирует через `diagnostics: _FakeDiagnosticsService` (не factory — screen не владеет, тест сам управляет) + inject-able `logProvider` + `shareInvoker`. Кейсы: рендер 3 статусов, фильтр ERROR оставляет только ERROR, `LogEntryTile` отображает level/timestamp/message раздельно, tap share → counter инкрементируется и текст содержит '# Stealth Diagnostics Report', empty-state, semantics smoke, **lifecycle test**: после dispose screen, fake.dispose НЕ вызван (screen не владел).

### Phase 5 — Integration, regression, docs

- [x] **Task 11** — `client/lib/local_app_service.dart` + `client/lib/ui/screens/settings_screen.dart`: добавить **factory method** `createDiagnostics()` (НЕ геттер на single instance — см. M1 Pass 5: lifecycle утечка). Factory собирает `DiagnosticsService` через method tear-offs. **БЕЗ `_diagnostics` final поля и БЕЗ изменений в `logout()`** — он не владеет инстансом. В Settings — добавить `OutlinedButton.icon` рядом с «Open WebRTC diagnostics» (`settings_screen.dart:383`) с label `'Open diagnostics & logs'`; навигация передаёт `diagnosticsFactory: _appService.createDiagnostics` в DiagnosticsScreen — screen сам создаёт и dispose'ит. **Старый webrtc_diagnostics_screen НЕ трогаем.**
- [x] **Task 12** — Regression-гейты: `flutter pub get`, `flutter analyze` (0 warnings), `flutter test test/security/no_bare_logging_test.dart`, новые тесты, полный `flutter test`. ci.yml не менять.
- [x] **Task 13** — `docs/diagnostics.md` + обновление `.ai-factory/DESCRIPTION.md` (новые файлы в «Ключевые файлы», абзац про buffer+scrubber в «Текущая архитектура»). README остаётся как landing page.

### Manual checkpoint

- **Task 14** — Ручной smoke на web + Android (iOS если доступен): рендер, фильтры, реальный share intent с .txt, проверить отсутствие full UUID в экспортированном отчёте (открыть в Telegram-черновике и поискать паттерн).

## Dependency Graph

```
15 (pubspec) ──► 6 (env)
15 (pubspec) ──► 8 (share)
17 (p2p api) ──► 3 (service)
16 (scrubber) ──► 5 (composer)
1 (buffer) ─────► 9 (UI)
3 (service) ────► 9 (UI)
```

Phase 0 (Task 15 + Task 17) — параллельно, не зависят друг от друга; первым на конвейере. Phase 1+2 — параллельны между собой кроме связок 16→5 и 17→3. Phase 3+4 — после своих зависимостей. Phase 5 — в конце.

## Commit Plan

> 17 задач → commit-чекпоинты каждые 3–4 задачи. Manual smoke (Task 14) не порождает коммит.

- **Commit 1** — после Task 15 + Task 17 + Task 1 + Task 2: `chore(deps)+feat(logging): pubspec deps, p2p health api, log ring-buffer`
- **Commit 2** — после Task 16 + Task 3 + Task 4: `feat(diagnostics): service status aggregator + inline log scrubber`
- **Commit 3** — после Task 5 + Task 6 + Task 7: `feat(diagnostics): report composer with env info`
- **Commit 4** — после Task 8 + Task 9 + Task 10: `feat(diagnostics): share action + screen with filter`
- **Commit 5** — после Task 11 + Task 12 + Task 13: `feat(diagnostics): wire into settings + docs`

После Commit 5 запустить Task 14; результаты в PR description.

## Definition of Done

- [ ] `flutter analyze` чисто;
- [ ] `flutter test` зелёный (старые + новые);
- [ ] `no_bare_logging_test` зелёный (никаких `print()`/`debugPrint()` вне `lib/logging/`);
- [ ] Экран открывается из Settings, рендерит статусы + логи, фильтр работает;
- [ ] Share button открывает системный share-sheet с .txt; экспортированный текст НЕ содержит сырых UUID/PB-id (inline-scrub применился);
- [ ] `docs/diagnostics.md` написан, `DESCRIPTION.md` обновлён;
- [ ] Ручной smoke на web + Android пройден (Task 14).

## Out of scope

- Riverpod миграция (M16, отдельный план после M10 merge).
- Сетевая отправка отчёта на serverный sink — only share intent, без cloud backend (проектное правило, см. DESCRIPTION.md).
- Поглощение или удаление `webrtc_diagnostics_screen_*.dart` — оставляем как deep-dive ICE-диагностику.
- Реалтайм-стриминг логов в DevTools / remote logger.
- Audit existing `lib/` на inline-sensitive ids в `Logger.{warn,error}` messages — экспорт защищён scrubber'ом независимо от качества call sites.
- **Realtime signaling SSE health** — `WebRtcSignalingService` per-call lifecycle делает интеграцию нетривиальной; pocketbase config-check выступает заглушкой. Полноценный realtime status — отдельный план (требует публичного API в `IncomingCallSignalingService` + проброса через `CallManager`).
- **i18n / локализация UI** — все новые строки на английском, соответствуя текущей конвенции. Полная локализация (l10n) — отдельный план.
