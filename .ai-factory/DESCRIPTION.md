# Stealth Messenger

## Обзор

Stealth Messenger - Flutter-мессенджер с архитектурой local-first, E2E-шифрованием и WebRTC/P2P transport. Локальная идентичность создается на устройстве: UUID, X25519 keypair, nickname и контактный bundle. Приватный ключ не покидает устройство.

## Текущая архитектура

- Контакты и история сообщений хранятся локально через `LocalDatabaseService`.
- Пользовательский API для UI сосредоточен в `LocalAppService`.
- Сервисы регистрируются через Riverpod-DI в `client/lib/di.dart`. `runApp` обёрнут в `ProviderScope`, экраны (`profile_screen`, `settings_screen`, `contacts_screen`, `MyApp`) реализованы как `ConsumerStatefulWidget`. `chats_screen.dart` — единственный экран ещё на старом пути (queued follow-up).
- Обмен контактами идет через `stealth:<base64url(json)>` bundle с `user_id`, `name`, `public_key`.
- Сообщения и вложения шифруются E2E перед сохранением/передачей.
- Safety-number verification: `LocalAppService.getSafetyNumber/verifyContact/detectSafetyMismatch` + UI-диалог `safety_number_dialog.dart` + ✓/⚠ индикатор в списке контактов. Запись хранит `verified_at` и снимок `verified_safety_number`.
- Identity key rotation: `LocalAppService.rotateIdentityKeypair()` с 24-часовым grace окном для prev keypair и автоматическим fallback decryption на старый ключ. Кнопка "Rotate identity key" в Profile.
- P2P messaging использует WebRTC DataChannel.
- WebRTC signaling использует собственный PocketBase (`POCKETBASE_URL`) через SSE.
- Звонки идут через WebRTC; PocketBase хранит только временные signaling events. Серверный cron-хук `pb_hooks/rtc_cleanup.pb.js` чистит `rtc_signaling` старше 24 ч ежечасно.
- PocketBase identity: `users.id == pbIdFromLocalUuid(selfUserId)` (локальный UUID без дефисов) — это контракт между клиентом и API rules коллекции `rtc_signaling`, см. `client/lib/services/signaling/pb_user_id.dart` и `docs/POCKETBASE_SETUP.md`.
- Структурированное логирование через `client/lib/logging/logger.dart` (`Logger.debug/info/warn/error`) с auto-redaction sensitive ids выше DEBUG уровня. Прямой `print()` в `lib/` запрещён (project rule + regression test `client/test/security/private_key_no_export_test.dart`).
- Secure-storage политика: все sensitive ключи через `StorageService`, regression-тест `client/test/security/secure_storage_policy_test.dart` запрещает прямые `SharedPreferences` обращения по запрещённым именам.
- Web-сборка несёт строгий Content-Security-Policy meta в `client/web/index.html`; обоснование и smoke-проверка — `docs/web-csp.md`.
- Env-конфиг: committed `.env.defaults` (асет), runtime override через `--dart-define=<KEY>=value`. `.env` остаётся в `.gitignore` и больше не входит в asset bundle.

## Стек

- Dart / Flutter
- `flutter_riverpod` для DI и реактивных провайдеров (`client/lib/di.dart`)
- `cryptography` для X25519, AES-GCM и ratchet helpers
- `flutter_webrtc` для аудио/видео и DataChannel
- `pocketbase` для signaling
- `idb_shim`, `sqflite`, `path_provider` для локальной БД
- `flutter_secure_storage_x` и web storage abstraction для ключей
- `shared_preferences` и `flutter_dotenv` для локальных настроек

## Ключевые файлы

- `client/lib/main.dart` — bootstrap, `.env.defaults` + dart-define, startup recovery, `ProviderScope` корень
- `client/lib/di.dart` — Riverpod provider registry (storage / db / app service / p2p / incoming-message stream)
- `client/lib/local_app_service.dart` — local-first application facade (включая `verifyContact`, `rotateIdentityKeypair`, `SafetyNumberMismatch`, `IdentityRotationResult`)
- `client/lib/local_database_service.dart` — зашифрованное локальное хранилище + `testOverrides` seam для unit-тестов; `markContactVerified`, `clearAllContactsVerifiedAt`
- `client/lib/storage_service.dart` — экспорт + doc-комментарий с политикой sensitive-ключей
- `client/lib/p2p_service.dart` — WebRTC DataChannel messaging
- `client/lib/logging/logger.dart` — структурированный логгер + redaction
- `client/lib/services/signaling/webrtc_signaling_service.dart` — PocketBase signaling transport
- `client/lib/services/signaling/incoming_call_service.dart` — global incoming-call subscription
- `client/lib/services/signaling/pb_user_id.dart` — двунаправленная трансформация local UUID ↔ PB record id
- `client/lib/crypto/ratchet_service.dart` — symmetric KDF chain (НЕ Double Ratchet, без PFS; future-work в `.ai-factory/RESEARCH.md`)
- `client/lib/ui/screens/` — основные экраны (chats, calls, profile, settings, contacts)
- `client/lib/ui/screens/chats/` — выделенные модули chats (group sheets, `safety_number_dialog.dart`)
- `client/web/index.html` — CSP meta tag (см. `docs/web-csp.md`)
- `client/test/security/secure_storage_policy_test.dart` — regression guard для sensitive-key policy
- `pb_hooks/rtc_cleanup.pb.js` — версионированный PocketBase cron hook, TTL 24 ч для `rtc_signaling`
- `.github/workflows/ci.yml` — quality gate (analyze + test + build web + build apk + optional signaling smoke)

## Правило проекта

Серверного cloud-хранилища для контактов, истории сообщений, вложений и истории звонков больше нет. Новые изменения не должны добавлять внешний backend для этих данных без отдельного решения владельца проекта.
