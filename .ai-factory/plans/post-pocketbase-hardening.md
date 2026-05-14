# Post-PocketBase Hardening

**Branch:** `feature/pocketbase-signaling` (продолжаем текущую ветку, новая не создаётся)
**Created:** 2026-05-14
**Slug:** `post-pocketbase-hardening`

## Settings

- **Testing:** yes — unit + smoke где это применимо.
- **Logging:** verbose — DEBUG для signaling auth, bootstrap, refactor steps; redaction для user ids.
- **Docs:** yes — после Phase 6 обновить `docs/SECURITY.md`, `docs/POCKETBASE_SETUP.md`, `INSTALL_ANDROID.md`.

## Roadmap Linkage

- **Milestone:** none
- **Rationale:** В проекте отсутствует `.ai-factory/ROADMAP.md`; явная привязка не требуется. `/aif-verify --strict` должен сообщать WARN, не fail.

## Контекст и сверка рекомендаций с фактическим состоянием ветки

Внешний обзор оставил 8 рекомендаций. После сверки с кодом часть оказалась устаревшей или уже выполненной:

| #   | Рекомендация             | Статус                                                                                                                                                  |
| --- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | PocketBase identity/rules | **Реальный баг.** `_ensureAuth` создаёт PB-аккаунт без `id`, документ `docs/POCKETBASE_SETUP.md:146-150` утверждает обратное.                          |
| 2   | Plaintext key export      | **Уже устранено.** В `lib/` нет `stealth_private_key.txt`. `docs/SECURITY.md:22` фиксирует политику. Остаётся regression-guard.                          |
| 3   | Crypto claims sync        | **Реальный баг (но другой).** `docs/SECURITY.md` уже честный. Но `client/lib/crypto/ratchet_service.dart:4-10` утверждает Double Ratchet/PFS — это ложь. |
| 4   | Bootstrap                 | **Частично устранено.** Supabase env из `main.dart` убран. Остаётся `pubspec.yaml:106` объявляет `.env` как asset, при этом `.env` в `.gitignore`.       |
| 5   | CI                        | **Реально отсутствует.** Нет `.github/workflows/`.                                                                                                       |
| 6   | Split UI                  | **Реально.** `supabase_service.dart` удалён. Остаётся `chats_screen.dart` (1794), `webrtc_call_screen_web.dart` (1144), native (994).                    |
| 7   | Android release           | **Реально.** `applicationId = com.example.turbo`, release signed by debug key, lint отключён (`gradle.properties:5-6`).                                  |
| 8   | Logger/redaction          | **Частично.** Supabase bucket пункт неактуален (Supabase удалён). Остаётся: 7+ `debugPrint` с user ids; нужен logger c redaction.                         |

## Фазы и порядок

Цепочка зависимостей:

```
P1 (signaling id)  ─┐
P2 (CI)            ─┼─► P3 (bootstrap) ─► P4 (logger) ─► P5 (refactor) ─► P6 ─► P7 ─► P8
                    │
P1 + P2 идут раньше всего (P1 — критичный фикс, P2 даёт gate для всех остальных PR).
P4 (logger) должен быть готов до P5 (refactor использует его).
P6 (crypto docs) и P7 (key export guard) — независимы.
P8 (Android) — последний, изолированный.
```

## Phase 1 — Signaling identity (CRITICAL) ✅ done

**Цель:** `creator` и `target` в `rtc_signaling` должны совпадать с `request.auth.id`, чтобы продакшен-rules (см. `docs/POCKETBASE_SETUP.md:124-132`) не отбрасывали запросы.

### Task 1.1 — Прокидывать `id = selfUserId` в `_ensureAuth.create`

- **Файл:** `client/lib/services/signaling/webrtc_signaling_service.dart` (метод `_ensureAuth`, lines 280-334).
- **Что:** в `pb.collection('users').create(body: { ... })` добавить `'id': selfUserId`. Это привяжет PB-record id к локальному UUID, и `creator = selfUserId` будет равен `request.auth.id`.
- **Edge case:** PocketBase разрешает custom id только если длина 15+ символов и формат подходит. UUID v4 (32 hex char) подходит, но точки/тире нужно убрать. Стратегия: использовать `selfUserId.replaceAll('-', '')` для PB id и хранить связку.
- **Если PB отвергает custom id:** fallback ветка — хранить PB id отдельно от local UUID, использовать его в `creator/target`, а peer resolver мапит local UUID → PB id через contact bundle. Это альтернативный вариант (см. Task 1.2).
- **Логи (verbose):** `debugPrint('[signaling] ensureAuth create pbId=$pbId localId=$selfUserId')`.

### Task 1.2 — Migration path для уже зарегистрированных пользователей

- **Что:** для существующих установок `pb_user_id` в secure storage НЕ равен `selfUserId`. Нужен один из путей:
  - **A (предпочтительно):** при первом запуске после апдейта обнаружить mismatch, удалить старый PB-account (через admin API или авто-перерегистрацию по новому id), очистить `pb_token/pb_user_id/pb_password` и пройти flow заново. На приватном dev/test PocketBase это безопасно.
  - **B:** оставить старый PB id для backward-compat и завести второй ключ `pb_user_id_v2`, выбирать по версии.
- **Файл:** `client/lib/services/signaling/webrtc_signaling_service.dart` (новый helper `_migrateLegacyAuthIfNeeded`), вызывать из `_ensureAuth` до восстановления токена.
- **Логи (verbose):** `[signaling] legacy auth detected, migrating pbId=$old → $new`.

### Task 1.3 — Smoke-тест под production rules

- **Файл:** `client/test/services/signaling/pocketbase_signaling_smoke_test.dart` (расширить существующий).
- **Что:** добавить вариант теста, который перед прогоном выставляет на коллекции `rtc_signaling` rules в формате `@request.data.creator = @request.auth.id`. Тест должен проходить только если creator = PB id. Вариант:
  - сценарий 1 — strict rules + правильная identity (must PASS);
  - сценарий 2 — strict rules + неправильная identity (must FAIL с 403, fixture).
- **Когда запускать:** только если `POCKETBASE_TEST_URL` и `POCKETBASE_TEST_ADMIN_*` заданы. Иначе тест помечается `skip`.
- **Логи (verbose):** записывать каждое отправленное событие и серверный response в trace через тестовый logger.
- **Blocked by:** 1.1, 1.2.

**Phase 1 commit:** `fix(signaling): bind PocketBase user id to local UUID, add migration`.

## Phase 2 — CI gate ✅ done

**Цель:** дать gate для всех последующих изменений. Без CI пользователь не может запустить `flutter analyze/test` в текущей среде (нет Flutter в PATH).

### Task 2.1 — GitHub Actions workflow

- **Файл:** `.github/workflows/ci.yml` (создать).
- **Jobs:**
  - `analyze-and-test`: ubuntu-latest, `subosito/flutter-action@v2` (channel: stable), `flutter pub get` (в `client/`), `flutter analyze`, `flutter test --coverage`.
  - `build-web`: ubuntu-latest, `flutter build web --release`.
  - `build-android`: ubuntu-latest, JDK 17, `flutter build apk --debug`.
- **Triggers:** `push` на любой ветке, `pull_request` против `main`.
- **Кэш:** pub cache + gradle cache.
- **Логи:** workflow печатает версии flutter/dart и состояние `client/.env.example` (для отладки).

### Task 2.2 — Optional signaling smoke job

- **Файл:** `.github/workflows/ci.yml` (job `signaling-smoke`, отдельный).
- **Условие:** `if: ${{ secrets.POCKETBASE_TEST_URL != '' }}`.
- **Шаги:** прогонять `flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart` с пробросом env-секретов.
- **Не блокирует merge** при отсутствии секрета.

### Task 2.3 — README badge + раздел Status

- **Файл:** `README.md` (или `client/README.md`).
- **Что:** добавить badge статуса CI; раздел «Quality gates» с перечнем jobs.
- **Не обязательно**, но улучшает onboarding.

**Phase 2 commit:** `ci: add GitHub Actions for analyze/test/build` (+ doc badge).

## Phase 3 — Bootstrap hardening ✅ done

**Цель:** чистая `flutter build` без локального `.env` должна давать понятную ошибку, а не падать на ассете.

### Task 3.1 — Развести `.env` и assets

- **Файл:** `client/pubspec.yaml` (lines 104-107).
- **Опция А (рекомендуется):** убрать `- .env` из assets, а в `main.dart` загружать через `dotenv.load(fileName: '.env', mergeWith: const {})` с fallback на `.env.defaults` (commitable, без секретов).
- **Опция Б:** оставить asset, но добавить в репозиторий пустой `.env.defaults` и логику copy-on-build (Makefile / `tool/sync_env.sh`).
- **Зафиксировать в `client/.gitignore`:** `.env` остаётся ignored, `.env.example` и `.env.defaults` — нет.

### Task 3.2 — Аудит `.env.example`

- **Файл:** `client/.env.example`.
- **Что:** убедиться, что присутствуют все ключи из `docs/POCKETBASE_SETUP.md` и `.ai-factory/plans/pocketbase-signaling.md:24-34`:
  - `POCKETBASE_URL`
  - `TURN_URL`, `TURN_USERNAME`, `TURN_PASSWORD`
  - `TURNS_URL`, `TURNS_USERNAME`, `TURNS_PASSWORD`
- **Логи:** не требуются (статический файл).

### Task 3.3 — Startup error UX с указателем на setup-docs

- **Файл:** `client/lib/main.dart` (lines 60-67) — уже даёт текст; убедиться, что `StartupErrorScreen` отображает кнопку «View setup guide» с deep link на `docs/POCKETBASE_SETUP.md`.
- **Файл:** `client/lib/ui/screens/startup_error_screen.dart`.
- **Логи (verbose):** `[bootstrap] missing POCKETBASE_URL, opened setup guide`.

**Phase 3 commit:** `fix(bootstrap): defaults env + setup guide UX, decouple .env asset`.

## Phase 4 — Structured logger + redaction ✅ done

**Цель:** заменить разрозненный `debugPrint` единым модулем; не светить user_id в логах.

### Task 4.1 — Создать logger-модуль

- **Файл:** `client/lib/logging/logger.dart` (новый).
- **API:** `Logger.debug/info/warn/error('[scope] message', extras)`, уровень из env (`STEALTH_LOG_LEVEL=debug|info|warn|error`).
- **Redaction:** функция `redactId(String id)` → `'…${id.substring(id.length - 4)}'`; функция `redactBundle()`. По умолчанию автоматически редактирует ключи `userId`, `selfUserId`, `targetUserId`, `pbId`, `email`.
- **Output:** через `debugPrint`, чтобы вписаться в правило проекта (`.ai-factory/rules/base.md:40`).

### Task 4.2 — Мигрировать signaling

- **Файлы:** `client/lib/services/signaling/webrtc_signaling_service.dart`, `incoming_call_service.dart`, `peer_resolver.dart`.
- **Что:** заменить все `debugPrint('[signaling] ...')` на `Logger.debug('[signaling] ...', {userId: id})` с автоматическим redaction.
- **Логи (verbose):** при verbose режиме оставить полные id в DEBUG, но redactить в INFO/WARN.

### Task 4.3 — Мигрировать остальной `lib/`

- **Скоуп:** UI screens с user-id логами (`chats_screen.dart`, `profile_screen.dart`, `contacts_screen.dart`, `call_manager.dart` и др.).
- **Что:** заменить `debugPrint` → `Logger`. Где id в строке — extract в kv-extras.
- **Blocked by:** 4.1, 4.2.

### Task 4.4 — Тесты redaction

- **Файл:** `client/test/logging/logger_test.dart` (новый).
- **Кейсы:** `redactId('00112233-...-ffeeddcc') == '…ddcc'`; пустая строка → пустая; короткий id (<4 char) → весь редактируется в `…`.
- **Логи:** не нужны (тестовый сам себе logger).

**Phase 4 commit:** `feat(logging): structured logger with id redaction across lib/`.

## Phase 5 — Refactor крупных UI-файлов

**Цель:** снизить когнитивную нагрузку и улучшить покрытие тестами. Целевой размер модуля — до ~500 строк.

### Task 5.1 — Разрезать `chats_screen.dart` (1794 → ~4 файла) ✅ done

**Реальный исход:** двумя итерациями (group-sheets + conversation panel/footer/attachment).
`chats_screen.dart` сжат 1794 → 1153 строк (-36%). State остался в
`_ChatsScreenState`, разделение сделано через чистые stateless-widgets с
callback-проброс (notifier/controller-pattern не вводили — пробросом
параметров оказалось достаточно). Существующий
`chats_screen_semantics_test.dart` проходит без изменений; full
`flutter analyze` чист.

- **Файл-источник:** `client/lib/ui/screens/chats_screen.dart`.
- **Извлечено:**
  - `client/lib/ui/screens/chats/create_group_sheet.dart` (модальный шит создания группы).
  - `client/lib/ui/screens/chats/group_management_sheet.dart` (модальный шит управления участниками).
  - `client/lib/ui/screens/chats/conversation_panel.dart` (pinned banner + in-chat search + message list).
  - `client/lib/ui/screens/chats/conversation_footer.dart` (reply/edit banner + progress + typing + `GlassMessageInput`).
  - `client/lib/ui/screens/chats/conversation_attachment.dart` (image/audio/file билдер с авто-decrypt).
- **Не делали:** notifier/controller-абстракцию вокруг `_ChatsScreenState`
  (избыточно для текущего объёма; преждевременная абстракция).

### Task 5.2 — Разрезать `webrtc_call_screen_web.dart` (1144 → ~3 файла)

- **Файл-источник:** `client/lib/ui/screens/webrtc_call_screen_web.dart`.
- **Извлечь:**
  - `web_call_controller.dart` (peer connection, signaling wiring, lifecycle).
  - `web_call_media_bindings.dart` (track binding, audio routing, device selection).
  - `web_call_view.dart` (Widget-слой).
- **Тесты:** `webrtc_call_screen_semantics_test.dart` без изменений.

### Task 5.3 — Разрезать `webrtc_call_screen_native_impl.dart` (994 → ~3 файла)

- **Файл-источник:** `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`.
- **Извлечь по тем же осям, что и в web-варианте**: controller, media bindings, view.
- **Тесты:** semantics test + (новый) `webrtc_call_native_controller_test.dart` для пары публичных state transitions.

**Phase 5 commits (×3):**

1. `refactor(ui): split chats_screen into controller/composer/list`.
2. `refactor(ui): split webrtc_call_screen_web into controller/media/view`.
3. `refactor(ui): split webrtc_call_screen_native_impl into controller/media/view`.

## Phase 6 — Crypto claims × реальность ✅ done

**Цель:** убрать ложные claims о Double Ratchet и PFS из исходников и докуметов; зафиксировать настоящую модель.

### Task 6.1 — Переписать docstring `RatchetService`

- **Файл:** `client/lib/crypto/ratchet_service.dart` (lines 4-10).
- **Что:** убрать «Double Ratchet», «Perfect Forward Secrecy», «Старые ключи цепочки уничтожаются». Зафиксировать честно: «Stateless symmetric KDF chain on top of X25519 shared secret. NOT a Double Ratchet — нет DH-step, нет удаления state, root chain key компромиссит всю историю.»
- **Файл (опционально):** переименовать класс в `SymmetricKdfChain` или оставить `RatchetService`, но без претензий.

### Task 6.2 — Аудит claim-ов в репозитории

- **Команда recon:** `grep -rni "double.ratchet\|forward.secrecy\|PFS" client/ docs/ .ai-factory/`.
- **Действие:** в каждом найденном месте оставить точное описание текущего поведения. `docs/SECURITY.md` уже честный — проверить, что не появилось новых упоминаний.

### Task 6.3 — Future-work entry для настоящего DH ratchet

- **Файл:** `.ai-factory/RESEARCH.md` (создать, если нет) — секция «Crypto upgrade: real Double Ratchet (X3DH + DH step per message)».
- **Что зафиксировать:** scope, зависимости (нужен per-message DH-key exchange через DataChannel), миграция (rotation policy для активных чатов).
- **Не реализуем сейчас** — только зафиксировать.

**Phase 6 commit:** `docs(crypto): align RatchetService and docs with actual capability`.

## Phase 7 — Private key export regression guard ✅ done

**Цель:** не дать функции экспорта ключа вернуться в будущих PR.

### Task 7.1 — Static regression test

- **Файл:** `client/test/security/private_key_no_export_test.dart` (новый).
- **Что:** тест читает все файлы из `client/lib/` и `fail()` если встречает строки, выглядящие как persistance приватного ключа: `stealth_private_key`, `.writeAsString(.*privateKey`, `Clipboard.setData.*privateKey`, `share.*privateKey`.
- **Реализация:** через `Glob` + чтение файлов + `RegExp`. Тест быстрый, держится под 1 сек.

### Task 7.2 — Документировать политику

- **Файл:** `docs/SECURITY.md` (уже содержит на line 22). Добавить ссылку на test guard и инструкцию «как импортировать ключи правильно через encrypted backup» — в качестве future-work pointer.

**Phase 7 commit:** `test(security): regression guard against private key export`.

## Phase 8 — Android release hardening ✅ done

**Цель:** возможность собрать публичный APK без debug-keystore и с включённым lint.

### Task 8.1 — Заменить applicationId

- **Файл:** `client/android/app/build.gradle.kts` (lines 9, 24).
- **Что:** `namespace` и `applicationId` → `com.stealth.messenger` (или согласованное имя — спросить пользователя перед commit; default `com.stealth.messenger`).
- **Файл:** `INSTALL_ANDROID.md` — обновить package-id.
- **Зачем:** Play Store/F-Droid не примут `com.example.*`.

### Task 8.2 — Release signingConfig через `key.properties`

- **Файл:** `client/android/key.properties.example` (новый, committable).
- **Файл:** `client/android/app/build.gradle.kts` — читать `key.properties` (storeFile, storePassword, keyAlias, keyPassword), задать `signingConfigs.release { ... }`, и `release.signingConfig = signingConfigs.getByName("release")`.
- **Файл:** `client/android/.gitignore` — добавить `key.properties` и keystore-файлы.
- **Документация:** `docs/ANDROID_RELEASE.md` (новый) — пошагово как сгенерировать keystore (`keytool -genkey ...`).

### Task 8.3 — Включить lint release

- **Файл:** `client/android/gradle.properties` (lines 5-6).
- **Что:** удалить `android.lintOptions.checkReleaseBuilds=false` и `android.lintOptions.abortOnError=false` (или поставить в `true`).
- **Файл:** `client/android/app/build.gradle.kts` — добавить блок `lint { baseline = file("lint-baseline.xml"); checkReleaseBuilds = true; abortOnError = true }`.
- **Действие:** сгенерировать baseline через `./gradlew :app:updateLintBaseline` локально, чтобы существующие предупреждения не блокировали CI.
- **Blocked by:** 8.1 (применять после смены applicationId).

**Phase 8 commit:** `chore(android): release signing, lint, public applicationId`.

## Commit Plan

| #   | После задачи | Commit                                                                       |
| --- | ------------ | ---------------------------------------------------------------------------- |
| 1   | 1.1–1.3      | `fix(signaling): bind PocketBase user id to local UUID, add migration`       |
| 2   | 2.1–2.3      | `ci: add GitHub Actions for analyze/test/build`                              |
| 3   | 3.1–3.3      | `fix(bootstrap): defaults env + setup guide UX, decouple .env asset`         |
| 4   | 4.1–4.4      | `feat(logging): structured logger with id redaction across lib/`             |
| 5   | 5.1          | `refactor(ui): split chats_screen into controller/composer/list`             |
| 6   | 5.2          | `refactor(ui): split webrtc_call_screen_web into controller/media/view`      |
| 7   | 5.3          | `refactor(ui): split webrtc_call_screen_native_impl into controller/media/view` |
| 8   | 6.1–6.3      | `docs(crypto): align RatchetService and docs with actual capability`         |
| 9   | 7.1–7.2      | `test(security): regression guard against private key export`                |
| 10  | 8.1–8.3      | `chore(android): release signing, lint, public applicationId`                |

## Логирование (общая политика)

- Везде вместо `print()` использовать `Logger` (Phase 4).
- В `[signaling]`, `[bootstrap]`, `[call]`, `[contacts]`, `[crypto]` сообщениях редактировать любые user-id до последних 4 символов в уровнях INFO+, оставлять полным только в DEBUG.
- Никогда не логировать `privateKey`, `password`, `pb_token`, plaintext сообщений и attachment bytes.
- Это правило закреплено в `.ai-factory/rules/base.md:41`, Phase 4 даёт enforcement.

## Тестовая стратегия

- Все новые сервисы — unit tests рядом с источником (`client/test/...` зеркало).
- Существующие semantics-тесты должны выживать рефакторинг (Phase 5) без модификаций.
- Smoke test (`pocketbase_signaling_smoke_test.dart`) — расширяется в Phase 1.3.
- В CI (Phase 2) `flutter test` запускается на каждом push.

## Чего НЕ делаем в этом плане

- Не реализуем настоящий DH Double Ratchet (зафиксировано future-work, Phase 6.3).
- Не вводим внешний cloud backend (запрещено `base.md:13-16`).
- Не возвращаем Supabase ни в каком виде.
- Не добавляем in-app экспорт приватного ключа.

## Следующие шаги

```
/aif-implement
```

Будет идти по фазам в указанном порядке. После каждого commit-checkpoint следует ручная проверка (build/manual smoke) или CI после Phase 2.
