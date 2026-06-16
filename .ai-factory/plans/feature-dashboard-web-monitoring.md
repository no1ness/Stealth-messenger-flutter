# Dashboard Web Monitoring (dashboard.stealthpro.ru)

**Branch:** main (no branch)
**Created:** 2026-06-14
**Type:** Enhancement

## Description

Вынести мониторинг в отдельную веб-страницу `dashboard.stealthpro.ru`. Текущий `MonitoringScreen` читает только локальные данные устройства — на отдельной странице они бесполезны. Решение: клиент пушит статистику в PocketBase, а dashboard страница читает агрегированные данные оттуда.

## Settings

- Testing: yes
- Logging: verbose
- Docs: yes (mandatory checkpoint at end)

## Roadmap Linkage

**Milestone:** M11 — Web rollout readiness
**Rationale:** Performance benchmarks and monitoring dashboard are prerequisites for web release — provides quantifiable perf gates and visibility into real-world usage across platforms.

## Tasks

### Phase 1: Server — PocketBase collection `app_stats`

#### Task 1: Create `app_stats` collection schema

- [x] Create `server/pocketbase/app_stats_import.json`
- [x] Collection `type: base`, `system: false`
- [x] Fields:
  - `userId` (text, required) — local UUID пользователя
  - `deviceId` (text, required) — device ID (UUID v4)
  - `platformType` (text) — "android", "ios", "web", etc.
  - `osVersion` (text)
  - `deviceModel` (text)
  - `deviceBrand` (text)
  - `appVersion` (text)
  - `appBuildNumber` (text)
  - `chatCount` (number, required)
  - `contactCount` (number, required)
  - `messageCount` (number, required)
  - `callCount` (number, required)
  - `installCount` (number, required)
- [x] Index: `CREATE INDEX idx_app_stats_userId ON app_stats (userId)`
- [x] Rules:
  - `listRule`: `""` (публичный доступ — stats не чувствительны)
  - `viewRule`: `""` (публичный)
  - `createRule`: `@request.auth.id != ""`
  - `updateRule`: `null` (без обновлений — только insert)
  - `deleteRule`: `null` (без удаления)
- [x] Docs: инструкция по импорту через PocketBase Admin UI (Settings → Import collections → загрузить JSON)
- Files: `server/pocketbase/app_stats_import.json`
- Logging: Logger.info на стороне клиента при создании записи
- Depends on: nothing

### Phase 2: Client — отправка статистики в PocketBase

#### Task 2: Create `AppStatsPushService`

- [x] Create `client/lib/services/monitoring/app_stats_push_service.dart`
- [x] Singleton, принимает `PocketBase?` (по умолчанию `PocketBaseClient.instance.pb`)
- [x] Метод `pushStats()`:
  - Берёт `DashboardService().getDashboardSummary()` (все 15 полей)
  - POST в `/api/collections/app_stats/records` через `_pb.collection('app_stats').create(body: {...})`
  - Оборачивает в try/catch — при ошибке `Logger.warn` (нефатально, пушинг не должен ломать приложение)
- [x] Логирование:
  - `Logger.debug` при успешной отправке
  - `Logger.warn` при ошибке (с телом ошибки)
  - `Logger.info` при первом запуске пушера
- Files: `client/lib/services/monitoring/app_stats_push_service.dart`
- Logging: verbose (debug на успех, warn на ошибку)
- Depends on: Task 1 (коллекция должна существовать на сервере)

#### Task 3: Wire `AppStatsPushService` into `LocalAppService`

- [x] Добавить поле `AppStatsPushService? _statsPusher` (nullable, создаётся только если есть PocketBase URL)
- [x] В `startPBBasedWorkers()` (после presence heartbeat):
  ```dart
  _statsPusher = AppStatsPushService();
  await _statsPusher!.pushStats(); // immediate first push
  _statsPushTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
    await _statsPusher?.pushStats();
  });
  ```
- [x] Поле `Timer? _statsPushTimer`
- [x] В `logout()`: отмена таймера `_statsPushTimer?.cancel()`
- Files: `client/lib/local_app_service.dart`
- Logging: Logger.info при старте пушера, Logger.debug при каждом пуше
- Depends on: Task 2

### Phase 3: Dashboard web page

#### Task 4: Create `MonitoringDataService`

- [x] Create `client/lib/services/monitoring/monitoring_data_service.dart`
- [x] Читает из PocketBase коллекцию `app_stats`:
  - `getAllStats()` — GET `app_stats?sort=-created&perPage=200` → список последних записей
  - `getAggregated()` — считает на клиенте: total users (distinct userId), total chats, messages, calls
  - `getPlatformBreakdown()` — распределение по платформам
- [x] Кэширует результаты в памяти (in-memory cache, 30s TTL)
- [x] Обработка ошибок: пустой массив при ошибке, Logger.warn
- Files: `client/lib/services/monitoring/monitoring_data_service.dart`
- Logging: verbose
- Depends on: Task 1 (коллекция должна существовать)

#### Task 5: Create entry point `lib/main_monitoring.dart`

- [x] Create `client/lib/main_monitoring.dart`
- [x] Минимальный bootstrap (без регистрации, без LocalAppService логики):
  - `WidgetsFlutterBinding.ensureInitialized()`
  - `dotenv.load(fileName: '.env.defaults')` + `applyDartDefineOverrides()`
  - `runApp(DashboardApp())` — `MaterialApp` с единственным экраном
- [x] Вынес `_applyDartDefineOverrides()` в общий `bootstrap_env.dart`
- [x] DashboardApp — простая обёртка с `LiquidTheme`, `ThemeController`
- [x] Home — новый `DashboardHomeScreen`
- [x] `DashboardHomeScreen` — StatefulWidget с автообновлением (10 сек)
- Files:
  - `client/lib/main_monitoring.dart`
  - `client/lib/ui/screens/dashboard/dashboard_home_screen.dart`
- Logging: Logger.debug при обновлении данных, Logger.warn при ошибке
- Depends on: Task 4

#### Task 6: Create `web/dashboard.html`

- [x] Create `client/web/dashboard.html`
- [x] Копия `web/index.html` с изменениями:
  - `<title>Stealth Dashboard</title>`
  - `<meta name="description" content="Stealth Dashboard - Monitoring and performance metrics">`
  - `<meta name="apple-mobile-web-app-title" content="Stealth Dashboard">`
  - Заголовок и preconnect ссылки те же (signal.stealthpro.ru)
- [x] `flutterConfiguration` с `canvaskit` renderer
- [x] Base href: `$FLUTTER_BASE_HREF`
- Files: `client/web/dashboard.html`
- Depends on: Task 5

### Phase 4: Build & Deploy

#### Task 7: Create `build-client-dashboard.sh`

- [x] Create `server/docker/scripts/build-client-dashboard.sh`
- [x] Копия `build-client-web.sh` с изменениями:
  - `--entry-point lib/main_monitoring.dart`
  - `-o build/dashboard` (выходная директория)
  - После сборки: `cp web/dashboard.html build/dashboard/index.html`
  - Те же `--dart-define` переменные
  - Лог: `[build-client-dashboard]`
- [x] После сборки: `ls -lh build/dashboard/`
- Files: `server/docker/scripts/build-client-dashboard.sh`
- Depends on: Task 5, Task 6

#### Task 8: Create `deploy-dashboard.sh`

- [x] Create `server/docker/scripts/deploy-dashboard.sh`
- [x] Паттерн как в `deploy-web.sh`:
  1. `build-client-dashboard.sh`
  2. `ssh mkdir -p /var/www/stealth-dashboard`
  3. `rsync -avz --delete build/dashboard/ root@VPS:/var/www/stealth-dashboard/`
  4. SSH-heredoc для /etc/caddy/Caddyfile — добавить site block
  5. `systemctl reload caddy`
  6. curl verify `https://dashboard.stealthpro.ru/`
- [x] Переменные: `DASHBOARD_DOMAIN`, `WEB_DOMAIN`
- Files: `server/docker/scripts/deploy-dashboard.sh`
- Depends on: Task 7

#### Task 9: Caddy config — dashboard.stealthpro.ru

- [x] Site block для dashboard (в deploy-dashboard.sh)
  ```
  dashboard.stealthpro.ru {
      root * /var/www/stealth-dashboard
      file_server
      encode gzip
  }
  ```
- [x] Добавить в Caddyfile через `deploy-dashboard.sh` (Task 8)
- [ ] **Внешнее** (не в коде): DNS A-запись `dashboard.stealthpro.ru → 186.246.51.39`
- Files: нет (генерируется скриптом)
- Depends on: Task 8

### Phase 5: Tests

#### Task 10: Tests for `AppStatsPushService`

- [x] Create `client/test/services/monitoring/app_stats_push_service_test.dart`
- [x] Mock PocketBase client (через `_FakePocketBase`)
- [x] Test: `pushStats()` вызывает `collection('app_stats').create()` с правильными полями
- [x] Test: ошибка PocketBase не бросает исключение наружу (graceful handling)
- [x] Test: ошибка stats provider не бросает исключение
- Files: `client/test/services/monitoring/app_stats_push_service_test.dart`
- Depends on: Task 2

#### Task 11: Tests for `MonitoringDataService`

- [x] Create `client/test/services/monitoring/monitoring_data_service_test.dart`
- [x] Mock PocketBase client
- [x] Test: `getAllStats()` возвращает список записей
- [x] Test: `getAggregated()` корректно считает distinct userId и суммы
- [x] Test: `getPlatformBreakdown()` считает по платформам
- [x] Test: пустой ответ от PocketBase не падает
- Files: `client/test/services/monitoring/monitoring_data_service_test.dart`
- Depends on: Task 4

## Commit Plan

| # | Tasks | Commit Message |
|---|-------|----------------|
| 1 | 1 | `feat(pocketbase): add app_stats collection schema for dashboard monitoring` |
| 2 | 2, 3 | `feat(monitoring): add AppStatsPushService - periodic stats push to PocketBase` |
| 3 | 4, 5, 6 | `feat(dashboard): add standalone Flutter web entry point for dashboard.stealthpro.ru` |
| 4 | 7, 8, 9 | `feat(deploy): add build/deploy scripts for dashboard.stealthpro.ru` |
| 5 | 10, 11 | `test(monitoring): add AppStatsPushService and MonitoringDataService tests` |
