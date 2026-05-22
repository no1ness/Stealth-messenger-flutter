# Stealth Messenger

## Обзор

Stealth Messenger - Flutter-мессенджер с архитектурой local-first, E2E-шифрованием и WebRTC/P2P transport. Локальная идентичность создается на устройстве: UUID, X25519 keypair, nickname и контактный bundle. Приватный ключ не покидает устройство.

## Текущая архитектура

- Контакты и история сообщений хранятся локально через `LocalDatabaseService`.
- Пользовательский API для UI сосредоточен в `LocalAppService`.
- Обмен контактами идет через `stealth:<base64url(json)>` bundle с `user_id`, `name`, `public_key`.
- Сообщения и вложения шифруются E2E перед сохранением/передачей.
- P2P messaging использует WebRTC DataChannel.
- WebRTC signaling использует собственный PocketBase (`POCKETBASE_URL`) через SSE.
- Звонки идут через WebRTC; PocketBase хранит только временные signaling events.
- PocketBase identity: `users.id == pbIdFromLocalUuid(selfUserId)` (локальный UUID без дефисов) — это контракт между клиентом и API rules коллекции `rtc_signaling`, см. `client/lib/services/signaling/pb_user_id.dart` и `docs/POCKETBASE_SETUP.md`.
- Структурированное логирование через `client/lib/logging/logger.dart` (`Logger.debug/info/warn/error`) с auto-redaction sensitive ids выше DEBUG уровня. Прямые `print()`/`debugPrint()` в `client/lib/` запрещены (project rule + regression test `client/test/security/no_bare_logging_test.dart`; allow-list — только сам `lib/logging/logger.dart`). Уровень переопределяется через `--dart-define=STEALTH_LOG_LEVEL=debug|info|warn|error`.
- Env-конфиг: committed `.env.defaults` (асет), runtime override через `--dart-define=<KEY>=value`. `.env` остаётся в `.gitignore` и больше не входит в asset bundle.

## Стек

- Dart / Flutter
- `cryptography` для X25519, AES-GCM и ratchet helpers
- `flutter_webrtc` для аудио/видео и DataChannel
- `pocketbase` для signaling
- `idb_shim`, `sqflite`, `path_provider` для локальной БД
- `flutter_secure_storage_x` и web storage abstraction для ключей
- `shared_preferences` и `flutter_dotenv` для локальных настроек

## Ключевые файлы

- `client/lib/main.dart` — bootstrap, `.env.defaults` + dart-define, startup recovery
- `client/lib/local_app_service.dart` — local-first application facade; постепенно становится тонким делегатом поверх доменных сервисов
- `client/lib/services/identity/identity_service.dart` — own user_id / nickname / X25519 keypair + contact-bundle generation (вынесен из LocalAppService task #5)
- `client/lib/services/contacts/contact_service.dart` — peer bundles, nicknames, safety numbers, search; `decodeContactBundle()` — pure top-level helper (task #5)
- `client/lib/services/messaging/message_service.dart` — encrypt/decrypt/send/edit/delete/pin/get-messages для 1:1; групповая криптография инжектируется через `attachGroupCrypto()` (task #6)
- `client/lib/crypto/aes_bytes.dart` — top-level `encryptBytesWithSecret` / `decryptBytesWithSecret` (AES-GCM-256), используется и message, и group, и attachment слоями (task #6)
- `client/lib/services/attachments/attachment_service.dart` — uploadBytes/download/compactDescriptor/getStorageDebugSummary; групповой ключ инжектируется через `attachGroupKeyResolver()` (task #7)
- `client/lib/services/calls/call_history_service.dart` — запись incoming/declined/ended звонков + getRecentCallHistory (task #7)
- `client/lib/services/chat_management/chat_management_service.dart` — private/group chat lifecycle (findOrCreatePrivateChatWith / createGroupChat / member-role mgmt); групповой секрет инжектируется через `attachGroupSecretKeyResolver()` (FIX_PLAN A1)
- `client/lib/services/dashboard/dashboard_service.dart` — analytics rollups (getDashboardSummary / getWeeklyActivityBars / getLastSeen / countUnreadSince); pure aggregator `computeWeeklyBars()` доступен top-level для unit-тестов (FIX_PLAN A2)
- `client/lib/services/crypto/group_secret_service.dart` — owner группового секрета (in-memory cache + `flutter_secure_storage_x` persist); экспортирует `resolve()` / `encryptForGroup()` / `decryptForGroup()` / `clearOnLogout()`. Используется MessageService, AttachmentService, ChatManagementService через callback injection из LocalAppService ctor (FIX_PLAN D1)
- `client/lib/services/webrtc/ice_config.dart` — top-level `buildIceServers()` (STUN + TURN/TURNS from `.env`), используется и `P2PService`, и `NativeCallMediaBindings` (task #8)
- `LocalDatabaseService` schema v6: top-level `deliveryStatus` поле + `lastRetryAttemptedAt` (для outgoing 1:1 only) + индекс `deliveryStatus` для pending-queue worker; legacy rows без поля читаются как `sent` (task #8, готовит почву под task #9 retry)
- `client/lib/local_database_service.dart` — зашифрованное локальное хранилище
- `client/lib/p2p_service.dart` — WebRTC DataChannel messaging
- `client/lib/logging/logger.dart` — структурированный логгер + redaction
- `client/lib/services/signaling/webrtc_signaling_service.dart` — PocketBase signaling transport
- `client/lib/services/signaling/incoming_call_service.dart` — global incoming-call subscription
- `client/lib/services/signaling/pb_user_id.dart` — двунаправленная трансформация local UUID ↔ PB record id
- `client/lib/crypto/ratchet_service.dart` — symmetric KDF chain (НЕ Double Ratchet, без PFS; future-work в `.ai-factory/RESEARCH.md`)
- `client/lib/ui/screens/` — основные экраны (chats, calls, profile, settings, contacts)
- `client/lib/ui/screens/chats/` — выделенные модули chats (group sheets)
- `.github/workflows/ci.yml` — quality gate (analyze + test + build web + build apk + optional signaling smoke)

## Правило проекта

Серверного cloud-хранилища для контактов, истории сообщений, вложений и истории звонков больше нет. Новые изменения не должны добавлять внешний backend для этих данных без отдельного решения владельца проекта.
