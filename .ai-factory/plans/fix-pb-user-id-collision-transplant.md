# Plan: PB User ID Collision Fix — transplant from fix/pb-user-id-collision-fit

**Branch:** `main` (direct transplant, no feature branch)
**Created:** 2026-06-14
**Mode:** full

## Цель

Трансплантировать функциональные изменения из ветки `fix/pb-user-id-collision-fit` в `main`.
Main сильно изменился с момента создания ветки, поэтому прямой merge невозможен —
только хирургический перенос логики.

Ветка содержит 4 коммита, из которых 2 функциональных (`ae47280`, `58d2049`) и 2 документационных
(`48a0815`, `d202bc2`).

## Суть изменений

1. **pb_user_id.dart** — замена strip-dashes (32 символа) на SHA-256 prefix (15 символов).
   PocketBase 0.23+ требует `id` длины ровно 15 символов, а UUID с дефисами даёт 32 → PB
   auto-generates другой id, ломая auth-контракт. `localUuidFromPbId()` заменяется на
   `PbUserIdResolver` (one-way hash, O(1) reverse lookup по известным UUID).

2. **pocketbase_auth_service.dart** — НОВЫЙ файл. Auth-логика, вынесенная из
   `WebRtcSignalingService` в отдельный синглтон, чтобы `WebRtcSignalingService` и
   `IncomingCallSignalingService` делили один in-flight guard.

3. **rtc_message.dart** — Опциональный `PbUserIdResolver` параметр для декодирования
   15-char PB id → local UUID.

4. **webrtc_signaling_service.dart** — Использует `PocketBaseAuthService`; добавляет
   `_knownUserIds` set; передаёт resolver в `RtcMessage.fromRecord`.

5. **incoming_call_service.dart** — `ensureAuth()` перед подпиской (иначе PB `listRule`
   отклоняет все входящие); `knownPeerUuidsProvider`; `creatorUuid` в payload.

6. **call_manager.dart** — Кеш контактов + `knownPeerUuidsProvider`.

7. **native/web_call_controller.dart** — `creatorUuid` в offer SDP.

8. **native/web_call_media_bindings.dart** — Guard пустых TURN credentials (иначе web
   падает при создании RTCPeerConnection).

9. **pubspec.yaml** — Добавить `crypto: ^3.0.0`.

## Settings

- **Testing:** yes (unit-тесты PbUserIdResolver + PocketBaseAuthService; регрессия по существующим signaling-тестам)
- **Logging:** verbose (`debugPrint` во всех ключевых точках: auth, resolver, creatorUuid injection, TURN guard)
- **Docs:** yes (mandatory docs checkpoint — обновить `docs/POCKETBASE_SETUP.md` с описанием 15-char SHA-256 id и `PbUserIdResolver`)
- **Roadmap linkage:** M3.1 (PB User ID Collision Fix — функционал из ветки `fix/pb-user-id-collision-fit`, на которую ссылается M3 как sealed, но код не попал в main)

## Roadmap Linkage

- **Milestone:** M3.1 — PB User ID Collision Fix
- **Rationale:** M3 (PocketBase identity hardening) помечен `[x]` sealed в ROADMAP.md и ссылается на hotfix-коммиты `ae47280`, `58d2049`, которые не были смержены в main. Данный план трансплантирует их функционал в main и закрывает M3.1.

## Затрагиваемые файлы

### Изменяемые (9 файлов):
- `client/pubspec.yaml` — добавить `crypto: ^3.0.0`
- `client/lib/services/signaling/pb_user_id.dart` — SHA-256 hash, PbUserIdResolver
- `client/lib/services/signaling/rtc_message.dart` — resolver param
- `client/lib/services/signaling/webrtc_signaling_service.dart` — PocketBaseAuthService
- `client/lib/services/signaling/incoming_call_service.dart` — auth + resolver
- `client/lib/ui/widgets/call_manager.dart` — contact cache
- `client/lib/ui/screens/calls/native_call_controller.dart` — creatorUuid
- `client/lib/ui/screens/calls/web_call_controller.dart` — creatorUuid
- `client/lib/ui/screens/calls/native_call_media_bindings.dart` — TURN guard
- `client/lib/ui/screens/calls/web_call_media_bindings.dart` — TURN guard

### Новые (1 файл):
- `client/lib/services/signaling/pocketbase_auth_service.dart` — shared auth singleton

### Тесты (2 файла):
- `client/test/services/signaling/pb_user_id_test.dart` — расширить существующие тесты
- `client/test/services/signaling/pocketbase_auth_service_test.dart` — НОВЫЙ

## Tasks

### Task 1 — Добавить `crypto` dependency

**Файл:** `client/pubspec.yaml`

Добавить `   crypto: ^3.0.0` в секцию `dependencies:` после строки `cryptography`.

**Логирование:** N/A

### Task 2 — НОВЫЙ файл pocketbase_auth_service.dart

**Файл:** `client/lib/services/signaling/pocketbase_auth_service.dart` (создать)

Перенести auth-логику из `WebRtcSignalingService`:
- Класс `PocketBaseAuthService` с конструктором `({PocketBase? pocketBase, StorageService? storage})`
- Статический синглтон `static final instance = PocketBaseAuthService();`
- Поле `_inFlight` — in-flight guard (предотвращает race при `users.create`)
- Метод `ensureAuth(String selfUserId)` — идемпотентный, гвардированный `_inFlight`
- Метод `_doEnsureAuth()` — логика: проверить authStore, restore из storage, или создать нового PB user с `id = pbIdFromLocalUuid(selfUserId)`
- `_migrateLegacyAuthIfNeeded()` — сбросить если stored PB-id не совпадает
- `_generatePassword()` — 24-char random
- Публичные константы `kPbTokenKey`, `kPbUserIdKey`, `kPbPasswordKey`

**Импорты:** `dart:math`, `package:flutter/foundation.dart`, `package:pocketbase/pocketbase.dart`, `package:stealth/services/signaling/pb_user_id.dart`, `package:stealth/storage_service_web.dart` (условный), внутренние пути.

**Логирование:** `debugPrint` при каждом ключевом шаге (`[auth] ensuring auth...`, `[auth] reused existing session`, `[auth] created PB user`, `[auth] migrated legacy auth`).

### Task 3 — SHA-256 hash + PbUserIdResolver в pb_user_id.dart

**Файл:** `client/lib/services/signaling/pb_user_id.dart`

Изменения:
1. Добавить импорты: `import 'dart:convert';` и `import 'package:crypto/crypto.dart';`
2. Заменить `_strippedUuidRegex` на `const int kPbIdLength = 15;`
3. Переписать `pbIdFromLocalUuid()`: если canonical UUID → `sha256.convert(utf8.encode(localUuid)).toString().substring(0, 15)`. Non-UUID passthrough.
4. Удалить `localUuidFromPbId()` (top-level function).
5. Добавить класс `PbUserIdResolver`:
   - Конструктор `PbUserIdResolver(Iterable<String> knownLocalUuids)` — хеширует каждый и строит `_pbToLocal` map
   - `static final empty = PbUserIdResolver([]);`
   - `String localUuidFromPbId(String pbId)` — lookup по map, passthrough если unknown
   - `bool knows(String pbId)` — проверка наличия в map

**Логирование:** `debugPrint` в конструкторе resolver (`[pb-id] resolver built with N entries`).

### Task 4 — Resolver param в rtc_message.dart

**Файл:** `client/lib/services/signaling/rtc_message.dart`

Изменения:
1. `factory RtcMessage.fromRecord(RecordModel record)` → `factory RtcMessage.fromRecord(RecordModel record, {PbUserIdResolver? resolver})`
2. В начале фабрики: `final r = resolver ?? PbUserIdResolver.empty;`
3. Заменить `localUuidFromPbId(record.getStringValue('creator'))` на `r.localUuidFromPbId(record.getStringValue('creator'))`
4. Аналогично для `target`.
5. Обновить doc-comment.

**Логирование:** `debugPrint` при fallback на `PbUserIdResolver.empty` (`[rtc] no resolver provided, using empty`).

### Task 5 — PocketBaseAuthService + _knownUserIds в webrtc_signaling_service.dart

**Файл:** `client/lib/services/signaling/webrtc_signaling_service.dart`

Изменения:
1. Добавить импорт `pocketbase_auth_service.dart`
2. Удалить поля/константы: `_kPbTokenKey`, `_kPbUserIdKey`, `_kPbPasswordKey`, `_storage`, `_authInFlight`
3. Удалить методы: `_ensureAuth`, `_doEnsureAuth`, `_migrateLegacyAuthIfNeeded`, `_generatePassword`
4. Добавить поле `final PocketBaseAuthService _authService;`
5. Добавить поле `final Set<String> _knownUserIds = <String>{};`
6. Обновить конструктор: добавить опциональный `authService` параметр, default `PocketBaseAuthService.instance` когда `pocketBase == null`
7. В `connect()`: `_knownUserIds.add(selfUserId);` и `await _authService.ensureAuth(selfUserId);`
8. В `_send()`: `_knownUserIds.add(targetUserId);`
9. В `_onRecord()`: создать `PbUserIdResolver(_knownUserIds)` и передать в `RtcMessage.fromRecord`

**Логирование:** `debugPrint` в `connect` (`[signaling] _knownUserIds size=N`), в `_onRecord` (`[signaling] resolved creator from resolver`).

### Task 6 — Auth + resolver + creatorUuid в incoming_call_service.dart

**Файл:** `client/lib/services/signaling/incoming_call_service.dart`

Изменения:
1. Добавить импорт `pocketbase_auth_service.dart`
2. Добавить поля: `_authService`, `_knownPeerUuidsProvider`
3. Обновить конструктор: опциональные `knownPeerUuidsProvider` (default `() => const <String>[]`) и `authService` (default `PocketBaseAuthService.instance`)
4. В `start()`: `await _authService.ensureAuth(selfUserId);` перед подпиской
5. В `declineCall()`: payload `{'creatorUuid': selfUserId}` вместо `const <String, dynamic>{}`
6. В `_onRecord()`: построить `knownUuids` из self + provider, создать `PbUserIdResolver`, передать в `fromRecord`. Для offer/hangup: предпочитать `payload['creatorUuid']` над `message.creator`

**Логирование:** `debugPrint` в `start` (`[incoming] ensureAuth done`), в `_onRecord` (`[incoming] resolved from creatorUuid/pb-id`).

### Task 7 — Contact cache в call_manager.dart

**Файл:** `client/lib/ui/widgets/call_manager.dart`

Изменения:
1. Поле `List<String> _knownContactUuidsCache = const <String>[];`
2. `_incomingCallService` → `late final` с `knownPeerUuidsProvider: () => _knownContactUuidsCache`
3. Метод `_refreshKnownContactsCache()` — `await _appService.getContacts()` → extract `user_id` строки
4. Вызов `_refreshKnownContactsCache()` в `_initGlobalCallListener()` перед подпиской

**Логирование:** `debugPrint` (`[call-manager] refreshed N contact UUIDs`).

### Task 8 — creatorUuid в offer SDP

**Файлы:**
- `client/lib/ui/screens/calls/native_call_controller.dart`
- `client/lib/ui/screens/calls/web_call_controller.dart`

В `_sendOffer()`: добавить `'creatorUuid': _selfUserId,` в enriched SDP payload.

**Логирование:** `debugPrint` (`[call] offer carries creatorUuid`).

### Task 9 — TURN credential guard

**Файлы:**
- `client/lib/ui/screens/calls/native_call_media_bindings.dart`
- `client/lib/ui/screens/calls/web_call_media_bindings.dart`

В `_appendTurnServer()`/`_appendWebTurnServer()`:
- Извлечь `user`/`pass` как non-nullable с `?? ''`
- Если `user.isEmpty || pass.isEmpty` → `debugPrint` skip message и `return`
- Использовать `user`/`pass` переменные в ice server конфиге

**Логирование:** `debugPrint` (`[ice] skipping TURN <url> — empty credentials`).

### Task 10 — Тесты PbUserIdResolver

**Файл:** `client/test/services/signaling/pb_user_id_test.dart` (расширить существующий)

Добавить тесты:
1. `pbIdFromLocalUuid returns 15-char SHA-256 hash for valid UUID`
2. `pbIdFromLocalUuid passes through non-UUID strings unchanged`
3. `PbUserIdResolver resolves known UUIDs`
4. `PbUserIdResolver.empty returns passthrough for unknown PB ids`
5. `PbUserIdResolver.knows returns correct boolean`
6. `canonical UUID regex still matches standard UUID format`

### Task 11 — Тесты PocketBaseAuthService

**Файл:** `client/test/services/signaling/pocketbase_auth_service_test.dart` (НОВЫЙ)

Тесты (mocked PocketBase):
1. `ensureAuth is idempotent when already authenticated`
2. `ensureAuth creates PB user when no existing session`
3. `static instance is a singleton`

## Commit Plan

11 задач → 2 коммита (на main напрямую):

```
commit 1: deps + core auth + id resolver
  Tasks 1-4: crypto dep, PocketBaseAuthService, pb_user_id, rtc_message

commit 2: wire services + media bindings + tests
  Tasks 5-11: webrtc_signaling, incoming_call, call_manager,
              call_controllers, media_bindings, tests
```

Suggested messages:

1. `fix(signaling): add PocketBaseAuthService singleton + SHA-256 PB user id resolver`

   Transplant from fix/pb-user-id-collision-fit (ae47280, 58d2049):
   - crypto: ^3.0.0 direct dependency
   - pocketbase_auth_service.dart: shared auth singleton with in-flight guard
   - pb_user_id.dart: SHA-256 prefix (15 chars) instead of strip-dashes; PbUserIdResolver
   - rtc_message.dart: optional resolver param for 15-char PB id → UUID resolution

2. `fix(signaling): wire PocketBaseAuthService + creatorUuid + TURN guard into services`

   Transplant from fix/pb-user-id-collision-fit (ae47280, 58d2049):
   - webrtc_signaling_service: use PocketBaseAuthService, _knownUserIds, resolver
   - incoming_call_service: ensureAuth before subscribe, resolver, creatorUuid
   - call_manager: contact cache + provider
   - call_controllers: symmetric creatorUuid in offer payload
   - media_bindings: skip TURN entries with empty credentials
   - Tests: PbUserIdResolver + PocketBaseAuthService coverage
