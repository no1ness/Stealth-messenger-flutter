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
- Структурированное логирование через `client/lib/logging/logger.dart` (`Logger.debug/info/warn/error`) с auto-redaction sensitive ids выше DEBUG уровня. Прямой `print()` в `lib/` запрещён (project rule + regression test `client/test/security/private_key_no_export_test.dart`).
- Env-конфиг: committed `.env.defaults` (асет), runtime override через `--dart-define=<KEY>=value`. `.env` остаётся в `.gitignore` и больше не входит в asset bundle.

## Стек

- Dart / Flutter
- `cryptography` для X25519, AES-GCM и ratchet helpers
- `flutter_webrtc` для аудио/видео и DataChannel
- `pocketbase` для signaling
- `idb_shim`, `sqflite`, `path_provider` для локальной БД
- `flutter_secure_storage_x` и web storage abstraction для ключей
- `shared_preferences` и `flutter_dotenv` для локальных настроек
- **Design system:** Geist + Geist Mono (SIL OFL 1.1, bundled под `client/assets/fonts/`) + `apple_liquid` design layer под `client/lib/themes/apple_liquid/`. Источник правды — `docs/design-system.md` (плюс HTML-mockups в `docs/design-mockups/`).
- **Testing:** `flutter_test` (axiom); `golden_toolkit` dev-dep для golden infra (Phase 9.0, инфра ready, visual-reel deferred).

## Ключевые файлы

- `client/lib/main.dart` — bootstrap, `.env.defaults` + dart-define, startup recovery
- `client/lib/local_app_service.dart` — local-first application facade
- `client/lib/local_database_service.dart` — зашифрованное локальное хранилище
- `client/lib/p2p_service.dart` — WebRTC DataChannel messaging
- `client/lib/logging/logger.dart` — структурированный логгер + redaction
- `client/lib/services/signaling/webrtc_signaling_service.dart` — PocketBase signaling transport
- `client/lib/services/signaling/incoming_call_service.dart` — global incoming-call subscription
- `client/lib/services/signaling/pb_user_id.dart` — двунаправленная трансформация local UUID ↔ PB record id
- `client/lib/crypto/ratchet_service.dart` — symmetric KDF chain (НЕ Double Ratchet, без PFS; future-work в `.ai-factory/RESEARCH.md`)
- `client/lib/ui/screens/` — основные экраны (chats, calls, profile, settings, contacts)
- `client/lib/ui/screens/chats/` — выделенные модули chats (group sheets)
- `client/lib/themes/apple_liquid/` — design-system layer: `constants/` (AppColors, AppSpacing, AppTypography, AppMotion, AppElevation, AppEffects, AppHaptics, GlassStyles), `widgets/` (GlassContainer, ChatTile, ContactTile, SectionHeader, StatusChip, ...), `feedback/` (showStealthSnackBar, showStealthDialog, StealthHaptics, StealthLoadingIndicator, StealthSkeletonTile), `effects/` (ScanlineOverlay, GrainOverlay, ChromaticAberration — signature visual moments, auto-disable в light brightness), `navigation/GlassPageRoute`, `motion/` (StaggeredListView, DecryptText)
- `docs/design-system.md` — source of truth для tokens, signature elements, dual-identity, performance discipline, accessibility contract
- `docs/design-mockups/` — visual HTML companion к design-system.md (8 standalone files, no build step)
- `.github/workflows/ci.yml` — quality gate (analyze + test + build web + build apk + optional signaling smoke)

## Правило проекта

Серверного cloud-хранилища для контактов, истории сообщений, вложений и истории звонков больше нет. Новые изменения не должны добавлять внешний backend для этих данных без отдельного решения владельца проекта.
