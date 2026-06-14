# Implementation Plan: Auto-contacts, presence & user directory

Branch: feature/auto-contacts-user-directory
Created: 2026-06-13

## Settings
- Testing: yes
- Logging: verbose
- Docs: yes (mandatory checkpoint)

## Roadmap Linkage
Milestone: "M17 — Auto-contacts, presence & user directory"
Rationale: Добавляет автоматическое отображение всех пользователей в контактах с online-статусом и детальной информацией (устройство, платформа, дата регистрации) для малой группы пользователей.

## Research Context
Source: .ai-factory/RESEARCH.md (не относится — фича новая, не из research)

Goal: Все существующие пользователи мессенджера автоматически отображаются в контактах с online-статусом и расширенной информацией.

Constraints:
- Мессенджер для малого количества людей — подходит централизованный подход через PocketBase
- PocketBase уже используется для signaling auth — расширяем его роль
- Серверного cloud-хранилища для контактов/сообщений быть не должно (project rule) — user_profiles хранит только мета-информацию и presence, не контакты/сообщения
- Все пользователи уже имеют PB аккаунт (создаётся в PocketBaseAuthService)

Architecture:
- Новая PB коллекция `user_profiles`: publicKey, deviceModel, platform, appVersion, registeredAt, isOnline, lastSeen
- `PresenceService` — владеет realtime подпиской на `user_profiles`, heartbeat (30с), AppLifecycleListener
- `UserDirectoryService` — fetch всех профилей, sync в локальные контакты, читает кэшированные данные от PresenceService
- `ContactService` — расширяется `addOrUpdateContact()` для auto-populated контактов
- UI: ContactTile с online-индикатором, bottom sheet детальной информации пользователя
- Уже существующие сервисы: `DeviceInfoService` (deviceModel, platform, appVersion), `DeviceRegistryService` (deviceId), `PocketBaseClient.instance.pb` (PB SDK)

## Commit Plan
- **Commit 1** (after tasks 1-3): "feat(pb): add user_profiles collection, directory service, presence service, contact upsert"
- **Commit 2** (after tasks 4-5): "feat(core): publish profile on startup, wire services into LocalAppService + SSE reconnect"
- **Commit 3** (after tasks 6-8): "feat(ui): presence indicators, user detail sheet, contacts screen update"
- **Commit 4** (after task 9): "test: add tests for user directory, presence, and UI components"
- **Commit 5** (after task 10): "docs: add user_profiles schema and architecture docs"

## Tasks

### Phase 1: PocketBase schema & core services

- [x] **Task 1: Create `user_profiles` PB collection + update setup docs**
  - Создать коллекцию `user_profiles` в PocketBase:
    - `userId` (text, unique, required) — локальный UUID владельца
    - `publicKey` (text) — X25519 публичный ключ для E2E (base64)
    - `deviceModel` (text) — модель устройства
    - `platform` (text) — android/ios/web
    - `appVersion` (text) — версия приложения
    - `registeredAt` (datetime) — когда создан профиль
    - `isOnline` (bool) — онлайн/оффлайн
    - `lastSeen` (datetime) — последняя активность
  - API rules:
    - List: `@request.auth.id != ""` (все аутентифицированные могут читать)
    - View: `@request.auth.id != ""`
    - Create: `@request.auth.id != "" && userId = pbIdFromLocalUuid(@request.auth.id)` (только свой профиль)
    - Update: `userId = pbIdFromLocalUuid(@request.auth.id)` (только свой профиль)
  - Обновить `docs/POCKETBASE_SETUP.md` — добавить схему коллекции и API rules
  - Создать конфигурационный файл/скрипт импорта коллекции (pb_schema.json)
  - *Файлы:* `docs/POCKETBASE_SETUP.md`, `docs/pb_schemas/user_profiles.json`
  - *Логирование:* `[user-profiles]` INFO о создании/обновлении профиля, WARN при ошибках API rules

- [x] **Task 2: Create `PresenceService` + `UserDirectoryService` (единая realtime подписка)**
  - `PresenceService` (singleton) — владеет PB realtime подпиской:
    - Конструктор: `PresenceService({PocketBase? pocketBase, StorageService? storage, Connectivity? connectivity})` — defaults `PocketBaseClient.instance.pb` / `StorageService()` / `Connectivity()` (паттерн как в `WebRtcSignalingService`). Создаёт `PocketBaseAuthService(pocketBase: pb, storage: storage)` внутри для вызовов `ensureAuth`.
    - `start(String selfUserId)` — принимает userId, вызывает `_authService.ensureAuth(selfUserId)`, затем:
      - `_subscribe()` — подписывается на PB realtime: `pb.collection('user_profiles').subscribe('*')` с обработкой ошибок (timeout, general). При ошибке — `_scheduleReconnect()`
      - `_subscribeReconnect()` — переподписка (сначала отменяет старую, затем вызывает `_subscribe()`)
      - Подписывается на `Connectivity().onConnectivityChanged` для авто-переподключения при восстановлении сети
    - `startHeartbeat()` — `Timer.periodic(30s)` → upsert своего профиля (`isOnline=true, lastSeen=now()`) в PB
    - **Upsert подход** (PocketBase не имеет native upsert): `findProfileByUserId(userId)`, если найден — `update(recordId, body)`, если нет — `create(body)`. Завести приватный метод `_upsertProfile(Map<String, dynamic> body)`.
    - **SSE reconnect** (паттерн из `WebRtcSignalingService`):
      - `_reconnectAttempt` (int), `_reconnectTimer` (Timer?), `_maxBackoffSeconds` (30)
      - `_scheduleReconnect({bool immediate = false})`: отменяет таймер, вычисляет задержку = `min(30, 2^_reconnectAttempt)`, устанавливает таймер
      - При успешной подписке сбрасывает `_reconnectAttempt = 0`
      - На `ConnectivityResult` change с hasNetwork — триггерит `_scheduleReconnect(immediate: true)`
    - `_disposed` флаг для guard от операций после dispose
    - `setOnline()` — upsert с `isOnline: true`, запускает heartbeat
    - `setOffline()` — upsert с `isOnline: false`, отменяет heartbeat, используется при AppLifecycleState.paused
    - AppLifecycleListener: `resumed→setOnline()`, `paused→setOffline()`
    - `dispose()` — отменяет таймер heartbeat, отменяет reconnectTimer, отписывается от connectivity, отписывается от SSE, закрывает стримы
    - `onPresenceChange` — `Stream<Map<String, dynamic>>` (изменения isOnline/lastSeen других пользователей)
    - *Файлы:* `client/lib/services/user_directory/presence_service.dart`
    - *Логирование:* `[presence]` DEBUG при heartbeat, INFO при online↔offline, WARN при ошибках upsert/subscribe/reconnect
  - `UserDirectoryService` (singleton) — читает данные, не подписывается на PB напрямую:
    - Конструктор: `UserDirectoryService({PocketBase? pocketBase, StorageService? storage})` — те же defaults. Создаёт `PocketBaseAuthService` внутри.
    - `fetchAllProfiles(String selfUserId)` — вызывает `_authService.ensureAuth(selfUserId)`, затем GET `pb.collection('user_profiles').getList()` с пагинацией, возвращает список Map
    - `syncToLocalContacts()` — upsert в локальные контакты через `ContactService.addOrUpdateContact()`:
      - Если контакт существует — обновить isOnline, lastSeen, deviceInfo, publicKey
      - Если новый — создать с `auto_populated: true` и всеми полями из профиля
    - Подписывается на `PresenceService.onPresenceChange` для обновления кэша в реальном времени
    - `getCachedProfiles()` — in-memory кэш профилей с полем `isOnline`
    - `clearCache()` — при logout
    - *Файлы:* `client/lib/services/user_directory/user_directory_service.dart`
    - *Логирование:* `[user-directory]` DEBUG при fetch/sync, INFO при новых контактах, WARN при ошибках PB

- [x] **Task 3: Add `ContactService.addOrUpdateContact()` method**
  - Новый публичный метод (независим от `_lastSearchResults`, в отличие от `addContact`):
    - `addOrUpdateContact(Map<String, dynamic> profile)` — принимает профиль из user_directory
    - Проверить существование: `_localDb.getContacts()` → найти по `contact_user_id == profile['userId']`
    - Если найден:
      - Не заменять ручное имя/nickname (пользователь мог вручную задать nickname)
      - Обновить поля: `isOnline`, `lastSeen`, `deviceInfo` (deviceModel, platform, appVersion), `publicKey`
      - Сохранить через `_localDb.saveContact(updatedContact)` — IndexedDB `put()` с keyPath `contact_user_id` работает как upsert
    - Если не найден:
      - Создать с полями из профиля + `auto_populated: true`
      - Маппинг полей: `profile.userId → contact_user_id`, `profile.deviceModel → deviceModel`, и т.д.
    - Не удалять ручные контакты, у которых нет профиля в PB
  - *Файлы:* `client/lib/services/contacts/contact_service.dart`
  - *Логирование:* `[contacts]` DEBUG при upsert, INFO при создании нового auto-populated контакта

### Phase 2: Bootstrap & integration

- [x] **Task 4: Add `_publishOwnProfile()` to `LocalAppService`**
  - Реализовать приватный метод `_publishOwnProfile(String userId)` в `LocalAppService`:
    - Получить pb: `final pb = PocketBaseClient.instance.pb;`
    - Вызвать `PocketBaseAuthService(pocketBase: pb, storage: StorageService()).ensureAuth(userId)`
    - Собрать DeviceInfo через уже существующий `DeviceInfoService.instance.getDeviceInfo()` (возвращает `DeviceInfo { platformType, deviceModel, appVersion }`)
    - Получить publicKey из `StorageService().read('publicKey')` — если null (корраптед storage), WARN и публиковать без publicKey
    - Получить deviceId из `DeviceRegistryService.instance.deviceId`
    - **try/catch:** обернуть целиком в try/catch с `Logger.warn` при ошибке — не блокировать startup
    - Upsert профиля (через `_upsertProfile` helper): userId, publicKey (если есть), deviceModel, platform, appVersion, registeredAt (из StorageService), isOnline=true
    - `registeredAt` — уже сохраняется в `IdentityService.registerUser()` в `StorageService` ключ `registeredAt`
  - Upsert helper (приватный статический или метод):
    - `_findProfileByUserId(String userId)` — GET `pb.collection('user_profiles').getFirstListItem('userId="..."')`
    - Если найден — `update(record.id, body)`, если нет — `create(body)`
  - **Publish guard:** сохранять timestamp последней успешной публикации в `_lastProfilePublishAt` (DateTime?). Если с последнего publish прошло < 5 минут — пропустить (WARN и return). Сбросить `_lastProfilePublishAt = null` при logout.
  - НЕ добавлять в `PocketBaseAuthService.ensureAuthenticated()` — это низкоуровневый метод для signaling, не для бизнес-логики
  - *Зависимость:* Task 4 → Task 5 (startPBBasedWorkers вызывает _publishOwnProfile)
  - *Файлы:* `client/lib/local_app_service.dart`
  - *Логирование:* `[profile-publish]` INFO при публикации профиля (новый vs обновление), DEBUG с данными устройства, WARN при ошибке или skip по guard

- [x] **Task 5: Wire services into `LocalAppService` + `startPBBasedWorkers()` + update `main.dart`**
  - В `LocalAppService`:
    - Добавить поля: `final _userDirectory = UserDirectoryService();` и `final _presence = PresenceService();` (singleton factory — возвращает `_instance`, как `_contacts = ContactService()`)
    - `_kickoffBackgroundWorkers()` остаётся без изменений (только `P2PService.startRetryWorker()` и `_attachments.evictOldBlobs()` — не зависят от PB/DeviceRegistry)
    - Добавить bool `_pbWorkersStarted = false` (guard)
    - Добавить публичный метод `startPBBasedWorkers()`:
      ```dart
      Future<void> startPBBasedWorkers() async {
        if (_pbWorkersStarted) return;
        _pbWorkersStarted = true;
        final me = await _identity.getUserId();
        if (me == null || me.isEmpty) return;
        try {
          await _publishOwnProfile(me);          // Task 4
          await _presence.start(me);              // subscribe SSE
          final profiles = await _userDirectory.fetchAllProfiles(me);
          await _userDirectory.syncToLocalContacts(profiles);
          _presence.startHeartbeat();             // periodic 30s
        } catch (error) {
          Logger.warn('[bootstrap] PB workers failed, will retry on next app start',
              extras: {'error': error});
        }
      }
      ```
    - В `logout()`:
      - `await _presence.setOffline()`  — дождаться подтверждения PB перед очисткой
      - `_presence.dispose()`
      - `_userDirectory.clearCache()`
      - Сбросить `_pbWorkersStarted = false`
      - Сбросить `_lastProfilePublishAt = null` (см. Task 4 publish guard)
  - В `main.dart._initializeApp()` после `DeviceRegistryService.instance.init()`:
    - Добавить: `await _appService?.startPBBasedWorkers();`
    - Добавить импорт `import 'package:stealth/services/device/device_info_service.dart'` (для DeviceInfo, может потребоваться в LocalAppService)
  - *Файлы:* `client/lib/local_app_service.dart`, `client/lib/main.dart`
  - *Логирование:* `[bootstrap]` INFO при старте/стопе workers, DEBUG при sync контактов

### Phase 3: UI

- [x] **Task 6: Update `ContactTile` with online/offline indicator**
  - Добавить параметр `isOnline` (bool?) в ContactTile
  - Если `isOnline == true` — зелёная точка (3px) в правом верхнем углу CircleAvatar
  - Если `isOnline == false` — серая точка
  - Если `isOnline == null` — без индикатора (legacy контакты без профиля)
  - Использовать `AppColors.systemGreen` / `AppColors.tertiaryLabel` из design system
  - Анимировать появление/исчезновение (AnimatedOpacity или FadeTransition)
  - **Accessibility:** обернуть индикатор в Semantics с label `AccessibilityIds.contactPresenceIndicator` (добавить новую константу в `AccessibilityIds`). Если isOnline == true — также `SemanticsProperties(button: false, label: 'Online')`. Если false — 'Offline'.
  - *Файлы:* `client/lib/themes/apple_liquid/widgets/contacts/contact_tile.dart`, `client/lib/constants/accessibility_ids.dart`
  - *Логирование:* не требуется (UI)
  - *Зависимость:* Task 8 читает поле `contact_user_id` из кэша — убедиться, что ContactTile не ломается при отсутствии `user_id` (null-safe userId fallback)

- [x] **Task 7: Create user detail bottom sheet**
  - `showUserDetailSheet(context, contact)` — функция bottom sheet:
    - CircleAvatar с инициалами
    - Имя пользователя (nickname)
    - User ID (моноширинный) — брать из `contact['user_id'] ?? contact['contact_user_id']`
    - Раздел "Устройство": deviceModel, platform
    - Раздел "Приложение": appVersion
    - Раздел "Активность": registeredAt (дата регистрации), lastSeen (последний раз онлайн), isOnline (статус)
    - Все поля опциональны — показывать только то, что есть (null-safe)
    - Кнопки действий: "Написать сообщение", "Позвонить" (если P2P ready)
    - Placeholder-кнопка "Редактировать профиль" (greyed out, `onTap: null`) — для будущей возможности редактировать device info. Не показывать для auto_populated контактов.
  - Использовать `GlassContainer` карточки и `StealthHaptics.lightTap()` на кнопках
  - Responsive: на телефоне bottom sheet, на планшете DraggableScrollableSheet
  - *Файлы:* `client/lib/ui/sheets/user_detail_sheet.dart`
  - *Логирование:* не требуется (UI)
  - *Зависимость:* Task 8 использует showUserDetailSheet при long-press

- [x] **Task 8: Update `ContactsScreen` — show all users + presence + auto_populated display**
  - **DataSource delegation:** добавить в `ContactsDataSource` и `LocalContactsDataSource` методы `getUserDirectoryService()` (возвращает `UserDirectoryService.instance`) и `getPresenceService()` (возвращает `PresenceService.instance`) — чтобы ContactsScreen мог подписываться на стримы. Либо экспортировать синглтоны напрямую (уже есть `UserDirectoryService.instance`, `PresenceService.instance`).
  - В `ContactsScreen.loadContacts()`:
    - После `_appService.getContacts()` загрузить `UserDirectoryService.instance.getCachedProfiles()`
    - Объединить списки: ручные контакты + auto_populated контакты
    - **Исключить дубли** (по `contact_user_id`): если ручной контакт и auto_populated имеют одинаковый `contact_user_id` — оставить ручной (с его nickname), но мержить isOnline/lastSeen/deviceInfo из кэша
    - **Визуальное отличие auto_populated:** контакты с `auto_populated == true` показывать с чуть меньшей непрозрачностью (0.85) и без кнопки "Remove" в action sheet (заменить на "Скрыть" — удаляет auto_populated контакт локально, но он вернётся при следующем sync)
    - Передавать `isOnline` в ContactTile из кэша профилей
    - При long-press на контакте — добавить пункт "Информация" → `showUserDetailSheet`
  - Search — искать по всем пользователям (ручным и auto_populated)
  - Real-time обновление статуса: подписаться на `PresenceService.instance.onPresenceChange` (один стрим на весь экран, фильтровать по userId контакта). **При получении события** — обновить `isOnline` и `lastSeen` в соответствующем контакте в `_contacts` и вызвать `setState()`.
  - **Memory management:** сохранять `StreamSubscription` в переменную экземпляра, отписываться в `dispose()`. Не создавать отдельную подписку на каждый контакт — использовать один общий стрим.
  - *Зависимость:* Task 8 → Task 6 (ContactTile с isOnline), Task 8 → Task 7 (showUserDetailSheet)
  - *Файлы:* `client/lib/ui/screens/contacts_screen.dart`, `client/lib/ui/screens/contacts_data_source.dart`
  - *Логирование:* DEBUG при обновлении списка контактов

### Phase 4: Tests & documentation

- [ ] **Task 9: Tests**
  - `PresenceService`:
    - Mock PB через `_FakePocketBase` (паттерн из `webrtc_signaling_service_test.dart`)
    - Mock `PocketBaseAuthService`
    - Mock `Connectivity` (для теста reconnect)
    - Test `setOnline()` вызывает upsert с `isOnline: true`
    - Test `setOffline()` вызывает upsert с `isOnline: false`
    - Test `startHeartbeat()` отправляет heartbeat каждые 30с (fake_async)
    - Test `dispose()` отменяет таймер и закрывает стримы
    - Test `onPresenceChange` стрим получает события realtime
    - Test reconnect: subscribe error → `_scheduleReconnect()` with exponential backoff (fake_async)
    - Test reconnect: connectivity restored → immediate reconnect
  - `UserDirectoryService`:
    - Test `fetchAllProfiles()` парсит ответ PB корректно
    - Test `syncToLocalContacts()` upsert новых и обновление существующих через `ContactService`
    - Test `getCachedProfiles()` возвращает кэшированные данные
  - UI:
    - Test ContactTile отображает/скрывает зелёную/серую точку
    - Test ContactTile online indicator accessibility label (Online/Offline)
    - Test ContactsScreen отображает auto-populated контакты
    - Test ContactsScreen: дубликаты (ручной + auto_populated) показываются один раз с приоритетом ручного
    - Test ContactsScreen: auto_populated контакты с reduced opacity
  - *Файлы:* `client/test/services/user_directory/presence_service_test.dart`, `client/test/services/user_directory/user_directory_service_test.dart`, `client/test/ui/contact_tile_test.dart`, `client/test/ui/contacts_screen_test.dart`
  - *Логирование:* не требуется (тесты)

- [ ] **Task 10: Documentation checkpoint**
  - Обновить `docs/POCKETBASE_SETUP.md` — добавить описание коллекции `user_profiles`, API rules, примеры
  - Дополнить `docs/` при необходимости — описать схему user directory и presence
  - Проверить консистентность docs с реализацией
  - *Файлы:* `docs/POCKETBASE_SETUP.md`, `docs/` при необходимости
  - *Логирование:* не требуется
