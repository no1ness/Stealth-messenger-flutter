# План: Фикс звонков/сообщений + E2E тестовая инфраструктура

**Branch:** `feature/fix-tests-calls-messages`
**Created:** 2026-06-18
**Backing plan:** `.ai-factory/plans/test-optimization-agent-plan.md`

## Roadmap Linkage

- **Milestone:** M12 — Two-device manual QA program
- **Rationale:** Фикс продакшн-звонков (rtc_signaling rules, user_profiles) и E2E тестовая инфраструктура — прямой prerequisite для двух-устройственного QA.

## Settings

- **Testing:** yes — тесты обязательны для каждого изменения
- **Logging:** verbose — DEBUG логи
- **Docs:** yes — обязательный docs checkpoint

---

## Phase 0 — Production fixes (calls & messages)

### Task 0.1: Commit existing production fixes `[x]`

**Что уже сделано:** rtc_signaling rules, user_profiles collection, PB hooks — всё закоммитить.

**Files (изменённые по `git status`):**
- `client/.env.defaults` — POCKETBASE_URL changed
- `client/android/app/build.gradle.kts` — debugSymbolLevel
- `client/pubspec.yaml` + `client/pubspec.lock` — fonts Geist/GeistMono
- `client/lib/themes/apple_liquid/widgets/circuit_board_background.dart` — Picture cache
- `client/lib/themes/apple_liquid/widgets/glass_app_bar.dart` — sigma 10→6
- `client/lib/themes/apple_liquid/widgets/glass_text_field.dart` — sigma 10→6
- `client/lib/themes/apple_liquid/widgets/debug_status_bar.dart` — sigma 10→6
- `client/lib/ui/screens/webrtc_call_screen_native_impl.dart` — sigma 10→6
- `client/lib/ui/screens/webrtc_call_screen_web.dart` — sigma 10→6
- `client/lib/themes/apple_liquid/widgets/call/call_hud_overlay.dart` — sigma 10→6
- `client/lib/services/diagnostics/diagnostics_share.dart` — misc fix
- `docs/PERFORMANCE.md` — benchmarks
- Various test files (staggered_list_view, update_prompt, native_call_controller, diagnostics_screen, contacts_screen, webrtc_call_screen)

**Validation:** `flutter analyze` 0 issues, `flutter test` passes.

---

### Task 0.2: Add BypassStateController.init() to main.dart startup `[x]`

**Что:** `BypassStateController.init()` никогда не вызывается при старте приложения. Это нужно для автоматического включения bypass-прокси (VLESS) при перезапуске, если пользователь ранее включил bypass в настройках.

**File:** `client/lib/main.dart`
**Change:** Добавить вызов `BypassStateController.init()` в `_initializeApp()`, после `await _checkRegistration()` и перед `WidgetsBinding.instance.addPostFrameCallback(...)`.

**Почему именно здесь:** `SharedPreferences` и env-переменные уже загружены на этом этапе, `BypassStateController.init()` прочитает сохранённое состояние bypass из `SharedPreferences` и применит его до запуска `startPBBasedWorkers()` (который идёт в post-frame callback).

**Logging:** `Logger.info('[bootstrap] bypass state initialized')`

**Validation:** `flutter analyze` passes.

---

### Task 0.3: Build debug APK + deploy for two-device testing `[x]`

**Что:** Собрать debug APK с dart-defines bypass и установить на два устройства для проверки звонков/сообщений.

**Commands:**
```bash
cd client
flutter build apk --debug \
  --dart-define=BYPASS_SERVER_IP=186.246.51.39 \
  --dart-define=BYPASS_UUID=8b07efcf-cf87-42e8-b9d6-dd0d6b8618b3 \
  --dart-define=BYPASS_PUBLIC_KEY=gkE3dgXxmY7ip63BIEf1zPfwi4Rq0o73n9eI7r7IbhY \
  --dart-define=BYPASS_SHORT_ID=8471221de9b86ec1
```

**Validation:** APK builds, installs on two devices. Проверить:
- контакты синхронизируются между устройствами
- звонки устанавливаются (WebRTC)
- сообщения доставляются (P2P DataChannel)

---

## Phase 1 — Test suite hardening

### Task 1.1: Run full test suite, fix regressions `[x]`

**Что:** Запустить полный `flutter test`, зафиксировать счёт. Если есть сломанные тесты после production фиксов — починить.

**Команда:** `wsl bash -c 'cd /home/ruslan/projects/STEALTH/client && flutter test'`

**Validation:** `flutter test` — не менее 296 pass, 0 fail.

---

### Task 1.1a: Refactor CallHistoryService for testability `[x]`

**Что:** `CallHistoryService` — singleton с hard-wired зависимостями (`LocalDatabaseService()`, `Uuid()`), без DI. Перед написанием тестов (Task 1.2) нужно добавить возможность инъекции fakes.

**File:** `client/lib/services/calls/call_history_service.dart`
**Change:**
- Добавить `@visibleForTesting` конструктор с опциональным `LocalDatabaseService?`:
  ```dart
  @visibleForTesting
  CallHistoryService.test({LocalDatabaseService? localDb})
    : _localDb = localDb ?? LocalDatabaseService(),
      _uuid = const Uuid();
  ```
- Сохранить существующий singleton как `factory CallHistoryService() => _instance;`

**Important — why not `_FakeLocalDb`:**
`LocalDatabaseService` — singleton с приватным generative-конструктором (`_internal()`). Dart запрещает extends класса с приватным конструктором из другого файла. Фейк-класс не может заменить `LocalDatabaseService` по типу.

**Решение:** в тестах использовать **реальный** `LocalDatabaseService` с inject-конструктором. `flutter test` запускается на хосте с `idbFactorySembastIo`, который работает с IndexedDB-подобной файловой БД. После каждого теста удалять созданные записи через `getCalls()` → `deleteCall()`.

**Pattern:** Inject через optional constructor parameter, следовать `webrtc_signaling_service_test.dart` / `_Harness` конвенции.

**Logging:** `Logger.debug('[call-history] test instance created')`

**Validation:** `flutter analyze` passes; существующий production код не меняет поведение.

---

### Task 1.2: Add call_history_service tests `[x]`

**Блокировано:** Task 1.1a (refactoring)

**Что:** Написать unit-тесты для `CallHistoryService`.

**File:** `client/test/services/calls/call_history_service_test.dart` (новый файл, создать `calls/` директорию)

**Тест-кейсы:**
- `recordIncomingCall` сохраняет запись с корректными полями
- `markIncomingCallDeclined` обновляет статус
- `markCurrentUserCallEnded` создаёт запись с direction='local'
- `getRecentCallHistory` возвращает лимитированный список, сортированный по дате
- Пустая история возвращает пустой список

**Pattern:** `_Harness` + `_FakeLocalDb` (hand-written fake, следуя конвенции `webrtc_signaling_service_test.dart`).

**Validation:** Новые тесты покрывают основные path + error cases.

---

### Task 1.3: Add user_directory_service tests for edge cases `[x]`

**Что:** Дополнительные edge case тесты для `UserDirectoryService.fetchAllProfiles`.

**File:** `client/test/services/user_directory/user_directory_service_test.dart`

**Тест-кейсы (добавить к существующим):**
- Профиль с `null`/пустыми полями (`publicKey: null`, `deviceModel: ''`) — не падает
- Профили с неполной схемой (missing fields) — обрабатывается без ошибки
- Профиль с невалидным `isOnline` значением (не bool) — не падает
- Пустой список профилей (уже есть test для ошибки PB, но не для пустого ответа)

**Validation:** Все edge case тесты проходят.

---

### Task 1.4: Add incoming_call_service subscription tests `[x]`

**Что:** Написать unit-тесты для `IncomingCallSignalingService`: подписка на `rtc_signaling` и обработка offer/hangup.

**File:** `client/test/services/signaling/incoming_call_service_test.dart` (новый файл)

**Тест-кейсы:**
- `start()` подписывается на `rtc_signaling` collection
- Получение `offer` события эмитит `IncomingCallOffer`
- Получение `hangup` события эмитит `IncomingCallHangup`
- События с `target != selfUserId` игнорируются
- `declineCall()` создаёт hangup запись в PB
- `stop()` отписывается от PB

**Pattern:** Следовать `_FakePocketBase` / `_FakeRecordService` / `_Harness` pattern из `webrtc_signaling_service_test.dart`.

**Validation:** Тесты проверяют subscribe/unsubscribe flow + event filtering.

---

## Phase 2 — TestController (debug-only test API)

### Task 2.1: Implement TestController class `[x]`

**Что:** Реализовать `TestController` — debug-only API для E2E тестов, управляющий клиентом через `window.test` (web) или HTTP (mobile).

**Files:**
- `client/lib/test_controller/test_controller.dart` — основной класс
- `client/lib/test_controller/test_event.dart` — модель событий
- `client/lib/test_controller/test_http_server.dart` — HTTP сервер для mobile

**Requirements:**
- `kDebugMode` guard только на точке подключения (в `main.dart`): `if (kDebugMode) { TestController.instance.attach(); }`
- Сами файлы компилируются unconditionally (Dart не имеет препроцессора)
- `window.test` для web (глобальная переменная в debug-сборке)
- Debug HTTP/WebSocket server на `localhost:9876` для mobile, с manage-методами (start/stop)
- Методы: `login(userId)`, `getBundle()`, `addContact(bundle)`, `sendMessage(to, text)`, `events` stream
- NOT available in release builds (проверить через `flutter build apk --release --analyze-size`)
- **Server lifecycle:** `TestController.startServer()` запускает HTTP сервер, `stopServer()` останавливает
- **⚠️ Main-isolate dispatch:** HTTP сервер работает в фоновом потоке. Все вызовы методов (`login`, `sendMessage`, etc.) обращаются к Flutter-сервисам, которые обязаны работать на main isolate. Диспатчить через:
  ```dart
  // В обработчике HTTP запроса:
  await Future.delayed(Duration.zero, () => service.method());
  // или scheduleMicrotask для fire-and-forget
  ```

**Logging:** `Logger.debug('[test-controller] ...')`

**Validation:** `flutter analyze` passes. Release build не содержит TestController в работающем состоянии.

---

### Task 2.2: Implement Event System `[x]`

**Что:** Детерминированная event-система для TestController.

**Files:**
- `client/lib/test_controller/test_event.dart` (дополнить)

**Events:**
- `MessageSent`, `MessageReceived`, `ContactAdded`
- `CallOfferCreated`, `CallAnswered`, `IceConnected`, `CallEnded`
- `Error`

**Requirements:**
- Каждый тип события реализует `Map<String, dynamic> toJson()` для HTTP-сериализации
- Event bus с возможностью подписки по типу: `waitForEvent("MessageReceived", timeout: 5000)`
- Фильтрация: игнорировать дубликаты по id

**Validation:** Events корректно эмитятся, сериализуются в JSON и фильтруются по типу.

---

### Task 2.3: Wire TestController into existing services `[x]`

**Что:** Подключить TestController к существующим сервисам через callback injection.

**Files:**
- `client/lib/main.dart` — инициализация TestController: `if (kDebugMode) { TestController.instance.attach(); }`
- `client/lib/services/contacts/contact_service.dart` — эмит `ContactAdded`
- `client/lib/services/messaging/message_service.dart` — эмит `MessageSent`/`MessageReceived`
- `client/lib/services/signaling/webrtc_signaling_service.dart` — эмит `CallOffer`/`CallAnswer`/`IceConnected`
- `client/lib/services/calls/call_history_service.dart` — эмит `CallEnded`

**Pattern:** **Setter-методы**, следуя конвенции `attachGroupEncryption()` в `message_service.dart` и `attachGroupKeyResolver()` в `attachment_service.dart`:
```dart
// В каждом сервисе:
void Function(TestEvent)? _onTestEvent;
void attachTestEventEmitter(void Function(TestEvent) cb) => _onTestEvent = cb;
```
**Не использовать конструктор** — сервисы уже имеют сложные конструкторы и singletons.

**Validation:** `flutter analyze` passes.

---

## Phase 3 — E2E test infrastructure

### Task 3.1: Set up Playwright + headless Web client `[x]`

**Что:** Создать базовую инфраструктуру для Playwright E2E тестов. Включает установку Playwright, конфигурацию и scripts для управления Flutter web dev server.

**Files:**
- `client/pw-test/package.json` — npm init + `@playwright/test` dependency
- `client/pw-test/playwright.config.mjs` — конфиг с Chrome args: `--use-fake-device-for-media-stream`, `--use-fake-ui-for-media-stream`
- `client/pw-test/core/client.mjs` — абстракция Web клиента
- `client/pw-test/core/events.mjs` — event bus
- `client/pw-test/core/webrtc.mjs` — WebRTC хелперы
- `client/pw-test/config.mjs` — конфиг (serverUrl, etc.)
- `client/pw-test/scripts/start-web-server.mjs` — запускает `flutter run -d web-server --web-port 4444 --web-renderer canvaskit` как child process
- `client/pw-test/scripts/stop-web-server.mjs` — останавливает dev server

**Requirements:**
- `npm install @playwright/test` + `npx playwright install chromium`
- Chrome launch args: `['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream']`
- Два изолированных browser context для двух клиентов
- Тест-раннер сначала запускает web dev server, ждёт `DevTools listening on ws://...`, выполняет тесты, останавливает server
- Поддержка `await client.waitForEvent("MessageReceived")`

**Validation:** Playwright скрипт может запустить Flutter web, залогинить двух пользователей и обменяться bundle.

---

### Task 3.2: Multi-client scenario runner `[x]`

**Что:** Абстракция для запуска multi-client сценариев.

**File:** `client/pw-test/core/runner.mjs`

**API:**
```js
const env = {
  createClient: async () => new Client(...),
};
await scenario(env);
```

**Validation:** Два клиента могут параллельно выполнять сценарии.

---

### Task 3.3: Basic E2E scenarios `[x]`

**Что:** Написать базовые E2E сценарии.

**Files:**
- `client/pw-test/scenarios/chat-basic.mjs` — отправка сообщения
- `client/pw-test/scenarios/call-basic.mjs` — WebRTC звонок
- `client/pw-test/scenarios/registration.mjs` — регистрация + bundle exchange

**Validation:** Сценарии проходят на локальной Web сборке.

---

## Phase 4 — Documentation & CI

### Task 4.1: Document test infrastructure `[x]`

**Что:** Документация по тестовой инфраструктуре.

**Files:**
- `docs/TESTING.md` — обзор: как запускать unit-тесты, E2E тесты, TestController API

**Validation:** Документация описывает все команды для запуска тестов.

---

### Task 4.2: Update CI with E2E tests `[x]`

**Что:** Добавить E2E тесты в GitHub Actions CI (web-only, fast path). Текущий CI работает только по `workflow_dispatch` — опционально добавить `push`/`pull_request` триггеры.

**File:** `.github/workflows/ci.yml`
**Change:**
- Добавить `on: [push, pull_request]` (или обсудить частоту с владельцем)
- Добавить job `pw-test-e2e` (ubuntu + node + playwright + flutter build web --release + npx playwright test)
- Job запускается только при изменениях в `client/pw-test/` или `client/lib/test_controller/`

**Validation:** CI прогоняет E2E сценарии на каждом PR.

---

## Commit Plan

| Commit | Tasks | Message |
|--------|-------|---------|
| Commit | Tasks | Message | Status |
|--------|-------|---------|--------|
| C1 | 0.1 | `chore: commit production fixes (rtc_signaling rules, user_profiles, perf)` | `[x]` |
| C2 | 0.2 | `fix: add BypassStateController.init() to app startup` | `[x]` |
| C3 | 1.1 | `test: run full suite, fix regressions` | `[x]` (311 pass, 0 fail) |
| C4 | 1.1a, 1.2 | `refactor: make CallHistoryService testable + add tests` | `[x]` |
| C5 | 1.3, 1.4 | `test: add edge case and incoming_call tests` | `[x]` |
| C6 | 2.1–2.3 | `feat: add TestController debug-only test API` | `[x]` |
| C7 | 3.1–3.3 | `test: add Playwright E2E infrastructure and scenarios` | `[x]` |
| C8 | 4.1–4.2 | `docs: add TESTING.md and CI integration` | `[x]` |

After C5 — build + deploy APK for two-device verification (Task 0.3, blocked).
