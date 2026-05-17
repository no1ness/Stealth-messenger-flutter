# Hardening: DI (Riverpod) + Secure-Storage policy + Safety numbers + Key rotation + PB TTL + Web CSP

**Branch:** `feature/hardening-di-secure-storage` (создаётся в Phase 0, off `main`)
**Created:** 2026-05-17
**Slug:** `hardening-di-secure-storage`

## Settings

- **Testing:** yes — unit-тесты для `LocalDatabaseService.saveMessage`, `CryptoHelper`, новых методов `LocalAppService` (safety-number persist, key rotation); widget-тест для `ProfileScreen` после Riverpod-миграции. P2P/signaling трогаем поверхностно — там уже есть smoke-тесты.
- **Logging:** verbose — `Logger.debug` для DI-bootstrap, secure-storage аудита, key rotation flow; `Logger.info` для пользовательских действий (rotate key, verify contact); `Logger.warn` для несовпадений safety-number и CSP-violations. **Прямой `print()`/`debugPrint()` в `lib/` запрещён правилом проекта** (см. `client/test/security/private_key_no_export_test.dart` regression guard).
- **Docs:** yes — после Phase 9 обновить `docs/SECURITY.md`, `docs/POCKETBASE_SETUP.md`, `docs/configuration.md`, новый `docs/web-csp.md`. `/aif-implement` обязан показать docs-checkpoint в конце.

## Roadmap Linkage

- **Milestone:** none
- **Rationale:** `.ai-factory/ROADMAP.md` в проекте отсутствует; явная привязка не требуется. `/aif-verify --strict` должен сообщать WARN, не fail.

## Контекст и сверка запроса с реальным состоянием кода

Запрос содержал 9 пунктов. После сверки с кодом часть формулировок оказалась неточной — план это учитывает:

| # | Запрос | Реальное состояние | Действие |
|---|--------|--------------------|----------|
| 1 | Внедрить DI + Riverpod/Provider, `di.dart`, ConsumerWidget | `flutter_riverpod` отсутствует в `pubspec.yaml`. Каждый экран сам создаёт `LocalAppService()`. `P2PService.instance` — singleton. `ChangeNotifier` есть у call controllers. | Добавить `flutter_riverpod`, создать `client/lib/di.dart` с провайдерами, обернуть `runApp` в `ProviderScope`, мигрировать 4 экрана + дочерние виджеты `chats/`. |
| 2 | Добавить `flutter_secure_storage`, использовать в `StorageService` | `flutter_secure_storage_x: ^12.1.5+0` **уже** подключён (`pubspec.yaml:42`) и используется в `storage_service_io.dart`. Все sensitive ключи (`privateKey`, `publicKey`, `pb_token`, `pb_password`, `pb_user_id`, `local_db_key`, `group_key_*`) уже идут через `StorageService`. | НЕ дублировать пакет. Закрыть остающиеся утечки: `themeMode` и `useP2P` читаются напрямую из `SharedPreferences` (low-sensitivity, можно оставить, но политика должна быть явной). Добавить regression-тест: ни один sensitive-ключ не пишется в `SharedPreferences` напрямую. |
| 3 | Safety-number verification | `LocalAppService.getSafetyNumber()` уже считает SHA-256 fingerprint (`local_app_service.dart:846-861`). UI отсутствует. У контактов нет поля `verified_at`. | Добавить UI экран/диалог, расширить `addContact()` и `saveContact()` полем `verified_at: ISO8601 \| null`, гейтить первое сообщение/звонок «непроверенному» контакту. |
| 4 | Key rotation API + UI + резерв старого ключа | Метода `rotateIdentityKeypair` нет. Есть `_sharedSecretCache` (`local_app_service.dart:24`), который надо инвалидировать. Identity не пересекается с PB-auth (та на UUID, не на ключе) — это упрощает rotation. | Добавить `LocalAppService.rotateIdentityKeypair({Duration gracePeriod})` с записью `privateKey_prev`/`publicKey_prev` + `prev_rotated_at`, UI-кнопкой в `profile_screen.dart`, обновлением QR/bundle и сбросом `_sharedSecretCache`. Дешифровка входящих в grace-period пробует prev-key fallback. |
| 5 | TTL-очистка PocketBase >24 ч | `docs/POCKETBASE_SETUP.md:189-199` описывает `pb_hooks/rtc_cleanup.pb.js` с TTL=1 ч, **но директории `pb_hooks/` в репозитории нет**. | Создать версионируемый `pb_hooks/rtc_cleanup.pb.js` с TTL=24 ч (как в запросе), синхронизировать `docs/POCKETBASE_SETUP.md`, добавить smoke-инструкцию вручную проверять cron в админке. |
| 6 | CSP для Web | `client/web/index.html` загружает только self-hosted `flutter_bootstrap.js`. Renderer=HTML (CI собирает без `--web-renderer=canvaskit`). Inline-CSS лоадер строки 23-55. Никакого `Content-Security-Policy` сейчас нет. | Добавить `<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss: https:; object-src 'none'; base-uri 'self'; frame-ancestors 'none';">`. `'unsafe-inline'` для style нужен из-за inline-CSS лоадера; `connect-src` `wss:`+`https:` нужен для PocketBase. Уточнено в задаче. |
| 7 | Покрыть критические модули тестами | Тестов для `LocalDatabaseService.saveMessage` и `CryptoHelper.encryptData/decryptData` нет (есть `crypto_test.dart` для X25519 ECDH end-to-end, но не для helper'а). Widget-теста `ProfileScreen` нет. | Создать `client/test/local_database_service_test.dart`, `client/test/helpers/crypto_helper_test.dart`, `client/test/widgets/profile_screen_test.dart` (с `ProviderScope` override после Phase 1-2). |
| 8 | Документировать новые шаги | `docs/SECURITY.md` секция "Хранение ключей" существует. Документации про CSP нет. | Обновить `docs/SECURITY.md`, добавить `docs/web-csp.md`, освежить `docs/POCKETBASE_SETUP.md` (TTL 24 ч), упомянуть rotate-key flow и safety-number UX в `docs/getting-started.md`. |

## Фазы и порядок

Цепочка зависимостей:

```
Phase 0 (branch)
  └─► Phase 1 (DI foundation)
       └─► Phase 2 (UI ConsumerWidget migration)
            ├─► Phase 4 (safety-number UI uses Phase 2 ProviderScope)
            └─► Phase 5 (rotate-key button in profile_screen — Phase 2)
  ├─► Phase 3 (secure-storage audit/regression) — независим от 1-2
  ├─► Phase 6 (PB TTL hook)                     — независим
  ├─► Phase 7 (Web CSP)                         — независим
  └─► Phase 8 (тесты)                           — после Phase 1-5
       └─► Phase 9 (docs)                       — финал, после всего

Параллелизация: 3, 6, 7 можно делать параллельно с 1-2. 4 и 5 требуют 2.
```

---

## Phase 0 — Branch setup

**Цель:** изолировать большой scope в новой ветке от `main`, не смешивая с уже идущими PB-id фиксами на `fix/pb-user-id-collision-fit`.

### Task 0.1 — Зафиксировать или отложить незакоммиченные docs/* ✅ done

- **Контекст:** на `fix/pb-user-id-collision-fit` сейчас `M docs/ARCHITECTURE.md`, `M docs/SECURITY.md` + новые `docs/{android-release,configuration,getting-started,pocketbase-setup,testing}.md`. Эти правки относятся к текущей PB-id ветке, не к новому скоупу.
- **Действие:**
  1. На текущей ветке `fix/pb-user-id-collision-fit` решить: коммитить эти изменения отдельным коммитом (`docs: ...`) или сделать `git stash push -u -m "wip-docs-pb-id"`.
  2. После решения — `git checkout main && git pull origin main`.
- **Логи (verbose):** перед каждой опасной командой выводить план через `Logger.info` (если запускается из dart-скрипта) или показывать ассистенту в чате.
- **Verify:** `git status` чист, `git rev-parse --abbrev-ref HEAD == main`.

### Task 0.2 — Создать ветку ✅ done

- **Команда:** `git checkout -b feature/hardening-di-secure-storage`.
- **Verify:** `git status` чист, branch=`feature/hardening-di-secure-storage`.

---

## Phase 1 — Riverpod DI foundation

**Цель:** ввести `flutter_riverpod` и единую точку регистрации сервисов; `ProviderScope` в корне; провайдеры для `LocalAppService`, `LocalDatabaseService`, `P2PService` без миграции экранов (миграция — Phase 2).

### Task 1.1 — Добавить зависимость `flutter_riverpod` ✅ done

- **Файл:** `client/pubspec.yaml` — в `dependencies:` добавить `flutter_riverpod: ^2.5.1` (актуальная мажорная 2.x; сверять с pub.dev перед PR).
- **Что:** `flutter pub get` локально, обновить `pubspec.lock`.
- **Логи:** `Logger.info('[di] added flutter_riverpod ^2.5.1')` в комментарии PR; в коде логов на этом шаге нет.
- **Verify:** `flutter analyze` зелёный.

### Task 1.2 — Создать `client/lib/di.dart` ✅ done

- **Файл:** новый `client/lib/di.dart`.
- **Что включить (провайдеры):**
  - `loggerProvider` (`Provider<Logger>`) — возвращает глобальный `Logger` из `client/lib/logging/logger.dart` (если уже singleton — `Provider((_) => Logger.instance)`).
  - `storageServiceProvider` (`Provider<StorageService>`) — `StorageService()` (та же фабрика, что используется в `LocalAppService` сейчас, см. `local_app_service.dart:18-23`).
  - `localDatabaseServiceProvider` (`Provider<LocalDatabaseService>`) — `LocalDatabaseService()`.
  - `localAppServiceProvider` (`Provider<LocalAppService>`) — `LocalAppService()` (внутри он сам строит `_storage`/`_localDb`; на этом этапе НЕ ломаем его конструктор, оборачиваем как есть).
  - `p2pServiceProvider` (`Provider<P2PService>`) — `P2PService.instance` (singleton оборачиваем, чтобы тесты могли override).
  - `pocketBaseAuthServiceProvider` (`Provider<PocketBaseAuthService>`) — `PocketBaseAuthService.instance` (та же логика — singleton под override).
  - **Stream-провайдер:** `incomingP2PMessagesProvider` (`StreamProvider<Map<String, dynamic>>`) — биндинг к `P2PService.instance.onMessage`. Это убирает ручную `StreamSubscription`-машинерию в `chats_screen.dart:37,68-90` после Phase 2.
- **Что НЕ делаем на этом шаге:**
  - НЕ переписываем `LocalAppService`/`P2PService` чтобы принимать зависимости через конструктор. Это refactor под Riverpod проводится плавно; сейчас провайдер только оборачивает существующие конструкторы.
- **Логи (verbose):** в `Provider` factory'ях — `Logger.debug('[di] resolving <name>')` (с осторожностью, чтобы не залить лог на каждый rebuild — `Provider` кеширует, так что вызов = init, это безопасно).

### Task 1.3 — Обернуть `runApp` в `ProviderScope` ✅ done

- **Файл:** `client/lib/main.dart`.
- **Что:** в `main()` заменить `runApp(MyApp())` на `runApp(ProviderScope(child: MyApp()))`. Внутри `_MyAppState` (`main.dart:136`) старое поле `_appService = LocalAppService()` оставить **временно** для backward-compatibility, пока экраны не переехали (Phase 2 уберёт это поле).
- **Логи (verbose):** `Logger.info('[di] ProviderScope mounted')` в `initState`.
- **Verify:** `flutter run -d chrome` и `-d android` — приложение стартует, ничего не сломано (экраны ещё не используют ref).

### Task 1.4 — Smoke-тест `ProviderScope` ✅ done

- **Файл:** новый `client/test/di_test.dart`.
- **Что:** в `ProviderContainer()` зачитать `localAppServiceProvider`, `p2pServiceProvider`, убедиться что они инстанцируются без exceptions.
- **Логи:** только assertions, без runtime-логов.

---

## Phase 2 — UI migration to ConsumerWidget

**Цель:** заменить `_appService = LocalAppService()` поля экранов на чтение из `ref.watch(localAppServiceProvider)`. Поток `P2PService.instance.onMessage` мигрировать на `ref.watch(incomingP2PMessagesProvider)`. Удалить дублирующие создания сервисов в дочерних виджетах.

### Task 2.1 — `profile_screen.dart` → `ConsumerStatefulWidget` ✅ done

- **Файл:** `client/lib/ui/screens/profile_screen.dart`.
- **Что:**
  - Заменить `extends StatefulWidget` на `extends ConsumerStatefulWidget`, `State<ProfileScreen>` на `ConsumerState<ProfileScreen>`.
  - Удалить поле `final LocalAppService _appService = LocalAppService();` (строка 24).
  - В методах вместо `_appService.xxx()` использовать `ref.read(localAppServiceProvider).xxx()` (для одноразовых вызовов в обработчиках) или `ref.watch(...)` в `build()`/в derived `FutureProvider`'ах (см. ниже).
  - Сделать `dashboardSummaryProvider` (`FutureProvider`) в `di.dart` для `getDashboardSummary()` — UI читает через `ref.watch`, никаких `_loadProfile` + `setState`.
- **Логи (verbose):** `Logger.debug('[ui:profile] rebuild')` на ключевых listener'ах (только для разработки, проверить редактор уровней).
- **Verify:** экран Profile открывается, отображает userId/nickname/QR, logout работает.

### Task 2.2 — `chats_screen.dart` → `ConsumerStatefulWidget` + StreamProvider

- **Файл:** `client/lib/ui/screens/chats_screen.dart`.
- **Что:**
  - Заменить на `ConsumerStatefulWidget`. Удалить `_appService = LocalAppService()` (строка 35).
  - **Главное:** убрать ручную подписку `_activeSubscriptions` (строка 37) и `_listenToP2PMessages()` (строки 68-90). Вместо этого внутри `build()` или derived `Consumer`-сегмента: `ref.listen(incomingP2PMessagesProvider, (prev, next) { next.whenData((msg) => _handleIncomingMessage(msg)); })`.
  - Адаптировать дочерние виджеты:
    - `client/lib/ui/screens/chats/conversation_panel.dart` (строка 43: параметр `appService`) → удалить параметр, использовать `ref.watch(localAppServiceProvider)`. Конструкторы вызывающих обновить.
    - `client/lib/ui/screens/chats/conversation_attachment.dart`, `create_group_sheet.dart`, `group_management_sheet.dart` — то же самое.
  - `P2PService.instance.isP2PReady(...)` (строки 575, 583) → `ref.watch(p2pServiceProvider).isP2PReady(...)`.
- **Логи (verbose):** `Logger.debug('[ui:chats] incoming p2p msg chatId=$chatId')` (auto-redaction позаботится о sensitive ids).
- **Verify:** список чатов + переписка + send + receive работают; P2P-индикатор корректно меняется.

### Task 2.3 — `settings_screen.dart` + `contacts_screen.dart` → `ConsumerStatefulWidget` ✅ done

- **Файлы:** `client/lib/ui/screens/settings_screen.dart`, `client/lib/ui/screens/contacts_screen.dart`.
- **Что:** аналогично 2.1; `themeMode`/`useP2P` остаются в `SharedPreferences` (см. Phase 3), но провайдер `themeModeProvider` (`StateProvider<ThemeMode>`) централизует доступ.
- **Verify:** переключение темы работает, toggle P2P сохраняется.

### Task 2.4 — Удалить устаревший `_appService` из `main.dart` ✅ done

- **Файл:** `client/lib/main.dart`.
- **Что:** убрать поле `_appService` (строка 136) и любую логику, которая на него опиралась. `MyApp` теперь чистый `ConsumerWidget`, который рутит дерево.
- **Verify:** `flutter analyze` зелёный, smoke на двух платформах.

---

## Phase 3 — Secure storage audit + regression guard

**Цель:** убедиться, что **ни один sensitive-ключ** не пишется напрямую в `SharedPreferences`, обойдя `StorageService`. Зафиксировать это политикой и regression-тестом.

### Task 3.1 — Документировать список sensitive-ключей ✅ done

- **Файл:** `client/lib/storage_service.dart` (в верхнем doc-комментарии).
- **Что:** добавить block-комментарий со списком ключей, для которых обязательно использовать `StorageService` (privateKey, publicKey, pb_token, pb_password, pb_user_id, local_db_key, group_key_*, в будущем privateKey_prev/publicKey_prev из Phase 5).
- **Также:** перечислить разрешённые SharedPreferences ключи (themeMode, useP2P) с пометкой "low-sensitivity UI prefs".

### Task 3.2 — Regression-тест: запрет sensitive ключей в `SharedPreferences` ✅ done

- **Файл:** новый `client/test/security/secure_storage_policy_test.dart`.
- **Что:** статически просканировать `client/lib/**/*.dart` (как делает `private_key_no_export_test.dart`) и поломать билд, если найден `SharedPreferences` вызов с одним из sensitive-ключей.
- **Стиль:** следовать `client/test/security/private_key_no_export_test.dart` (line-by-line scan через `Directory.listSync(recursive)` + regex match).
- **Логи в тесте:** при провале `expect`-сообщение должно показывать `file:line` нарушения.
- **Verify:** запустить `flutter test` — тест проходит (текущее состояние чистое).

### Task 3.3 — Не дублировать пакет

- **Файл:** `client/pubspec.yaml`.
- **Что:** **НЕ добавлять** чистый `flutter_secure_storage`. Используем существующий `flutter_secure_storage_x: ^12.1.5+0`. Если в запросе подразумевался переход с `_x` обратно на upstream — обсудить отдельно (форк существует из-за конкретных багфиксов). Зафиксировать решение комментарием в `pubspec.yaml`.

---

## Phase 4 — Safety-number verification

**Цель:** перед первым исходящим/входящим сообщением и звонком к контакту попросить пользователя сверить SHA-256 fingerprint. Сохранять `verified_at` в таблице контактов.

### Task 4.1 — Расширить схему контактов

- **Файл:** `client/lib/local_database_service.dart`.
- **Что:**
  - `saveContact` (строки 237-243) принимает уже `Map<String, dynamic>`, IndexedDB поддерживает динамические поля — никаких миграций не нужно.
  - Добавить методы: `Future<void> markContactVerified(String contactUserId, {required String safetyNumber, required DateTime verifiedAt})`, `Future<DateTime?> getContactVerifiedAt(String contactUserId)`.
  - Хранимые поля: `verified_at` (ISO8601 String), `verified_safety_number` (String — снапшот fingerprint в момент верификации, чтобы детектить mismatch после rotation).
- **Логи (verbose):** `Logger.info('[contacts] marked verified userId=<redacted> safetyNumber=<redacted>')`.

### Task 4.2 — API в `LocalAppService`

- **Файл:** `client/lib/local_app_service.dart`.
- **Что:**
  - `Future<bool> isContactVerified(String userId)` — true если `verified_at != null` и сохранённый `verified_safety_number` совпадает с текущим (т.е. ключи не менялись).
  - `Future<void> verifyContact(String userId)` — берёт текущий `getSafetyNumber(userId)` (строки 846-861), вызывает `_localDb.markContactVerified(...)`.
  - `Future<SafetyNumberMismatch?> detectSafetyMismatch(String userId)` — возвращает старый/новый fingerprint, если ключ контакта поменялся после верификации.
- **Логи:** `Logger.warn('[safety] mismatch userId=<redacted> prev=<short> curr=<short>')`.

### Task 4.3 — UI: диалог verify-fingerprint

- **Файл:** новый `client/lib/ui/screens/chats/safety_number_dialog.dart` (`ConsumerWidget`).
- **Что:** показать оба fingerprint'а (свой + контакта или общий SHA-256), QR-код фингерпринта, кнопки "Confirmed" / "Cancel".
- **Интеграция:** `chats_screen.dart`/`conversation_panel.dart` перед первой отправкой сообщения проверяет `isContactVerified`; если false — показывает `safety_number_dialog`, отправка возможна только после "Confirmed". То же для звонка: в `call_manager.dart` перед `dialOut`.
- **Логи (verbose):** `Logger.debug('[ui:safety] gate before sendMessage chatId=<redacted>')`.

### Task 4.4 — UI: индикатор verified в списке контактов

- **Файл:** `client/lib/ui/screens/contacts_screen.dart`.
- **Что:** рядом с именем — иконка ✓ если verified, иконка ⚠ + tooltip "Mismatch" если `detectSafetyMismatch` вернул значение.

---

## Phase 5 — Identity key rotation (с grace period для prev-key)

**Цель:** кнопка "Обновить ключ" в Profile. Новый identity X25519 keypair. Старый сохраняется в `privateKey_prev`/`publicKey_prev` на ограниченное время (24 ч), чтобы расшифровать сообщения, которые peer'ы отправили до того, как получили новый bundle.

### Task 5.1 — API `rotateIdentityKeypair`

- **Файл:** `client/lib/local_app_service.dart`.
- **Сигнатура:** `Future<RotationResult> rotateIdentityKeypair({Duration gracePeriod = const Duration(hours: 24)})`.
- **Поток:**
  1. Прочитать текущие `privateKey`/`publicKey` из StorageService.
  2. Сгенерировать новую `X25519().newKeyPair()`.
  3. В secure storage: `privateKey_prev = current_priv`, `publicKey_prev = current_pub`, `prev_rotated_at = DateTime.now().toIso8601String()`.
  4. Записать новые `privateKey`/`publicKey`.
  5. `_sharedSecretCache.clear()` (строка 24).
  6. Вернуть `RotationResult(newPublicKey, prevPublicKey, prevExpiresAt)`.
- **Cleanup expired prev:** в bootstrap'е (или ленивым check'ом в `_getOwnKeyPair`) удалять `privateKey_prev` если `prev_rotated_at + 24h < now`.
- **Логи (verbose):** `Logger.info('[identity] rotated; prev kept until=<iso>')`.

### Task 5.2 — Decryption fallback на prev-key

- **Файл:** `client/lib/local_app_service.dart`, в потоке `_getSharedSecret` / decryption.
- **Что:** при decryption failure (AEAD tag mismatch) и наличии `privateKey_prev` — попробовать derive shared secret через prev-keypair. Это безопасно: prev-key уже истекает по TTL, второй попытки на чужие данные не даём.
- **Логи:** `Logger.debug('[identity] decrypt fallback to prev-key contactId=<redacted>')`.

### Task 5.3 — UI кнопка в `profile_screen.dart`

- **Файл:** `client/lib/ui/screens/profile_screen.dart`.
- **Что:**
  - Кнопка "Обновить identity ключ" + объяснительный текст про последствия (контакты увидят `verified` mismatch, нужно будет переверифицировать; старый ключ хранится 24 ч).
  - Подтверждение через `AlertDialog`.
  - После rotation: показать `RotationResult`, перегенерировать QR (`generateQRCode()` автоматически возьмёт новый `publicKey`).
- **Логи (verbose):** `Logger.info('[ui:profile] user triggered rotateIdentityKeypair')`.

### Task 5.4 — Сброс `verified_at` у контактов после собственного rotate

- **Файл:** `client/lib/local_database_service.dart` + `local_app_service.dart`.
- **Что:** после успешного `rotateIdentityKeypair` обнулить `verified_at`/`verified_safety_number` у всех контактов (свой ключ изменился → safety number у всех другой). Альтернатива: оставить и опираться на `detectSafetyMismatch` для warning'а. **Решение:** сбрасывать `verified_at = null`, оставлять `verified_safety_number` как "last verified before rotation" для UI-сообщения.
- **Логи:** `Logger.info('[contacts] cleared verified_at for all contacts (self-rotation)')`.

---

## Phase 6 — PocketBase TTL hook (versioned)

**Цель:** добавить в репозиторий `pb_hooks/rtc_cleanup.pb.js` с TTL 24 ч (как в запросе). Сейчас хук только описан в docs, физически в репо его нет.

### Task 6.1 — Создать `pb_hooks/rtc_cleanup.pb.js` ✅ done

- **Файл:** новый `pb_hooks/rtc_cleanup.pb.js` (в корне проекта; рядом с `client/`, `docs/`).
- **Что (JS, PocketBase JS hooks API):**
  ```js
  cronAdd("rtcSignalingCleanup", "0 * * * *", () => {
    // every hour delete rtc_signaling rows older than 24h
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const records = $app.dao().findRecordsByExpr(
      "rtc_signaling",
      $dbx.exp("created < {:cutoff}", { cutoff })
    );
    records.forEach((r) => $app.dao().deleteRecord(r));
    console.log(`[rtcSignalingCleanup] deleted ${records.length} rows older than ${cutoff}`);
  });
  ```
- **Verify:** деплой инструкция в `docs/POCKETBASE_SETUP.md` (Task 9.x): положить файл в `pb_data/../pb_hooks/` рядом с бинарём.

### Task 6.2 — Обновить документацию TTL=24h ✅ done

- **Файл:** `docs/POCKETBASE_SETUP.md` (строки 189-199 сейчас 1h → переписать на 24h, добавить отсылку на `pb_hooks/rtc_cleanup.pb.js` в корне репо).

### Task 6.3 — Smoke-инструкция

- **Файл:** `docs/POCKETBASE_SETUP.md` — добавить раздел "Проверка cron": создать тестовый record с искусственным `created` в прошлом, дождаться следующего часа, убедиться что он удалён. Логи в admin UI → Logs.

---

## Phase 7 — Web CSP

**Цель:** ограничить web-bundle CSP так, чтобы любая XSS-попытка инжекта external скрипта была заблокирована.

### Task 7.1 — Добавить CSP meta в `client/web/index.html` ✅ done

- **Файл:** `client/web/index.html`.
- **Что:** в `<head>` после `<meta charset>` добавить:
  ```html
  <meta http-equiv="Content-Security-Policy"
        content="default-src 'self';
                 script-src 'self';
                 style-src 'self' 'unsafe-inline';
                 img-src 'self' data:;
                 connect-src 'self' wss: https:;
                 object-src 'none';
                 base-uri 'self';
                 frame-ancestors 'none';">
  ```
- **Почему такой набор:**
  - `script-src 'self'` — соответствует запросу. Flutter web bootstrap у нас self-hosted (`flutter_bootstrap.js`), CanvasKit не используется (HTML renderer в CI), `eval` не нужен.
  - `style-src 'self' 'unsafe-inline'` — обязательно из-за inline-CSS лоадера в `index.html:23-55`. Альтернатива (более чистая): вынести inline-CSS в `client/web/loading.css` + `<link>`, тогда можно убрать `'unsafe-inline'`. Рекомендуется в follow-up задаче.
  - `connect-src 'self' wss: https:` — PocketBase HTTPS + SSE; WebRTC сигнализация всё ещё HTTPS, WebRTC media каналы — UDP (CSP не покрывает).
  - `object-src 'none'`, `frame-ancestors 'none'`, `base-uri 'self'` — best-practice harden.
- **Логи:** в коде нет; в smoke-тесте проверить.

### Task 7.2 — Smoke: загрузка web после CSP ✅ done (docs/web-csp.md, consolidated with Phase 9 Task 9.2)

- **Файл:** ручная проверка через `flutter run -d chrome --web-renderer html`. Открыть DevTools → Console → убедиться что нет CSP violations. Зафиксировать в `docs/testing.md` (Phase 9) шаги smoke-проверки.

### Task 7.3 — (опционально, без блокировки) убрать `'unsafe-inline'` для styles

- **Файл:** `client/web/index.html` + новый `client/web/loading.css`.
- **Что:** вынести inline `<style>` в `loading.css`, добавить `<link rel="stylesheet" href="loading.css">`. После этого CSP можно ужать до `style-src 'self'`.
- **Решение по приоритету:** делать только если позволяет время; не блокирует Phase 7.1.

---

## Phase 8 — Тесты для критических модулей

**Цель:** покрыть unit-тестами `LocalDatabaseService.saveMessage` (полный roundtrip encrypt → save → load → decrypt), `CryptoHelper` (encryptData/decryptData edge cases), widget-тест `ProfileScreen` после Riverpod-миграции.

### Task 8.1 — `client/test/local_database_service_test.dart`

- **Файлы:** новый тест.
- **Что:**
  - Setup: `LocalDatabaseService` с in-memory `idb_shim` factory (или временной директорией sqflite). Если IDB-fallback требует pre-existing `local_db_key` в `StorageService` — заинжектить mock storage.
  - Cases:
    1. Encrypt-then-save roundtrip: `saveMessage(plaintext)` → `getMessages(chatId)` → расшифровать → сравнить.
    2. Dedup по `messageId`: дважды сохранить тот же messageId — в БД одна запись.
    3. Ordering по `created`.
    4. Soft-delete: `softDeleteMessage` помечает запись.
- **Логи в тесте:** `Logger.debug`-вывод можно глушить через test logger override (если у логгера есть `Logger.silent`).

### Task 8.2 — `client/test/helpers/crypto_helper_test.dart`

- **Файлы:** новый тест.
- **Что (`client/lib/helpers/crypto_helper.dart`):**
  - `generateSymmetricKey()` возвращает 32-байтный ключ, два вызова дают разные ключи.
  - `encryptData(data, key)` + `decryptData(...)` roundtrip для пустой, 1KB и 10MB строк.
  - `decryptData` бросает на изменённом ciphertext (tag mismatch).
  - `deriveKeyFromSeed(seed)` детерминистична: одинаковый seed → одинаковый ключ.
  - `encryptJson` / `decryptJson` roundtrip.

### Task 8.3 — `client/test/widgets/profile_screen_test.dart`

- **Файл:** новый тест (после Phase 2 migration).
- **Что:**
  - `ProviderScope` override для `localAppServiceProvider` → возвращает fake/mock `LocalAppService` с задаными `userId`, `nickname`, `generateQRCode` результатом.
  - `pumpWidget(ProviderScope(overrides: [...], child: MaterialApp(home: ProfileScreen())))`.
  - Assertions: текст `userId`, текст `nickname`, наличие QR-кода, кнопка logout вызывает `logout()` на mock.
- **Mock-стратегия:** без mocktail/mockito — простой `FakeLocalAppService extends LocalAppService` через `Mixin`-override методов; либо паттерн service-locator поверх `Provider.value`.

### Task 8.4 — CI: убедиться что новые тесты запускаются

- **Файл:** `.github/workflows/ci.yml` — `flutter test` уже там; новые тесты подберутся автоматически. Проверить что smoke job не таймаутится из-за крупного `crypto_helper_test` (10MB encrypt).

---

## Phase 9 — Документация

**Цель:** обновить docs так, чтобы новая политика (DI, Secure Storage, Safety Number, Key Rotation, TTL, CSP) была однозначно описана.

### Task 9.1 — `docs/SECURITY.md`

- **Файл:** `docs/SECURITY.md` (уже M в текущей ветке — координация с Phase 0 после слива).
- **Что добавить/обновить:**
  - Секция "Хранение ключей": подтвердить что `flutter_secure_storage_x` используется на iOS/Android, Web Crypto AES-GCM (non-extractable) на Web. Перечислить sensitive-ключи (точное соответствие списку в `client/lib/storage_service.dart` doc-комментарии после Task 3.1).
  - Секция "Safety Number / Verification": как пользователь верифицирует контакт, что значит `verified` icon, как detect mismatch.
  - Секция "Identity Key Rotation": кнопка + 24h grace period + последствия (re-verify).
  - Ссылка на новый `docs/web-csp.md`.

### Task 9.2 — `docs/web-csp.md`

- **Файл:** новый `docs/web-csp.md`.
- **Что:** скопировать финальный CSP из Task 7.1, объяснить каждый директив, описать как делать smoke-проверку (Task 7.2), upgrade path для Task 7.3 (вынести inline-CSS).

### Task 9.3 — `docs/POCKETBASE_SETUP.md`

- **Что:** обновлено в Task 6.2 (TTL=24h + ссылка на репо-файл).

### Task 9.4 — `docs/configuration.md` / `docs/getting-started.md`

- **Что:** упомянуть Riverpod в архитектуре, добавить onboarding-шаг "первый запуск → exchange contact bundle → verify safety number → отправить сообщение".

### Task 9.5 — `.ai-factory/DESCRIPTION.md`

- **Что:** добавить пункт о `client/lib/di.dart`, об экранов на `ConsumerWidget`, обновить раздел "Ключевые файлы".

---

## Commit Plan

План крупный — режем на 9 коммитов с явными чекпоинтами. Каждый коммит должен оставлять `flutter analyze` и `flutter test` зелёными.

| # | Phase | Что в коммите | Conventional commit |
|---|-------|----------------|---------------------|
| C1 | 0 | branch + (если нужно) commit pending docs/* | (отдельная PR на старой ветке или stash) |
| C2 | 1 | `flutter_riverpod` + `di.dart` + `ProviderScope` в `main.dart` + `di_test.dart` | `feat(di): introduce Riverpod ProviderScope and provider registry` |
| C3 | 2 | миграция profile/chats/settings/contacts экранов и дочерних виджетов на ConsumerWidget | `refactor(ui): migrate screens to Riverpod ConsumerWidget` |
| C4 | 3 | secure storage doc-policy + regression test | `test(security): regression guard for sensitive keys in SharedPreferences` |
| C5 | 4 | DB extension + LocalAppService API + UI dialog + verified indicator | `feat(security): safety-number verification flow with persistent verified_at` |
| C6 | 5 | `rotateIdentityKeypair` + prev-key fallback + UI button | `feat(security): identity keypair rotation with 24h grace period` |
| C7 | 6 | `pb_hooks/rtc_cleanup.pb.js` + docs update | `chore(pocketbase): version-control rtc_signaling TTL cleanup hook (24h)` |
| C8 | 7 | web CSP meta tag | `feat(web): add Content-Security-Policy meta tag` |
| C9 | 8 | unit + widget тесты | `test: cover LocalDatabaseService, CryptoHelper, ProfileScreen` |
| C10 | 9 | docs | `docs: update SECURITY.md, add web-csp.md, refresh setup docs` |

В одном PR можно слить C2..C10, или (предпочтительно) разбить на 2-3 stacked PR: `di+ui` (C2+C3), `security` (C4+C5+C6), `infra+docs` (C7+C8+C9+C10) — чтобы review был обозримым.

---

## Открытые вопросы / решения по умолчанию

1. **Версия `flutter_riverpod`:** в плане ^2.5.1; перед PR актуализировать до latest 2.x.
2. **`flutter_secure_storage` vs `_x`:** оставляем `_x`. Если нужен переход на upstream — отдельная задача.
3. **Grace-period prev-key 24 ч:** жёстко задан в `rotateIdentityKeypair`. Может оказаться слишком долгим для high-security сценария или слишком коротким для offline-сценария — параметризовано через `gracePeriod`, default настраивается там же.
4. **TTL=24 ч в PB hook:** соответствует запросу пользователя, отличается от текущей doc-цифры 1 ч — это документация была опережающей. Если 24 ч окажется слишком много для нагрузки PB — снизить в hook'е без миграции клиента.
5. **`'unsafe-inline'` в `style-src`:** временное компромиссное решение из-за inline-CSS лоадера; Task 7.3 — путь к полностью чистому CSP.
6. **`themeMode`/`useP2P` в SharedPreferences:** оставлены вне `StorageService` как явная политика "low-sensitivity UI prefs". Если в будущем добавятся пользовательские настройки, требующие приватности, — нужно расширить regression-тест (Task 3.2).
