# Local-First Stealth Architecture

**Last reconciled:** 2026-05-19
**Companion docs:** [`ARCHITECTURE.md`](./ARCHITECTURE.md) (layer/module diagram), [`SECURITY.md`](./SECURITY.md) (crypto + secret-handling), [`POCKETBASE_SETUP.md`](./POCKETBASE_SETUP.md) (signaling collection setup), [`../.ai-factory/ROADMAP.md`](../.ai-factory/ROADMAP.md) (milestone tracker).

This document is the source of truth for **what the local-first architecture commits to**. It is intentionally evergreen — when a new milestone seals, append to the "Shipped" log here; do **not** repurpose this file for transient task tracking. Task tracking lives in `.ai-factory/ROADMAP.md`.

## Цель

Закрепить архитектуру: local-first storage, E2E encryption, WebRTC/P2P delivery, PocketBase only for transient signaling.

## Project rule (неизменно)

Серверного cloud-хранилища для контактов, истории сообщений, вложений и истории звонков **больше нет**. Новые изменения не должны добавлять внешний backend для этих данных без отдельного решения владельца проекта.

## Shipped

### Архитектурная база (исходный rollout)

- Runtime client больше не инициализирует внешний cloud backend для контактов/истории.
- UI использует `LocalAppService`.
- Контактный обмен требует локальный contact bundle с public key (`stealth:<base64url(json)>` с `user_id`, `name`, `public_key`).
- WebRTC call signaling и DataChannel signaling идут через PocketBase.
- Удалены cloud sync service, cloud service facade, SQL migrations и старые diagnostic tools.

### PocketBase identity contract (post-pocketbase-hardening + hotfixes)

- PocketBase identity: `users.id == pbIdFromLocalUuid(selfUserId)` (15-char SHA-256 PB id) — закреплено как контракт между клиентом и rules коллекции `rtc_signaling` (см. `client/lib/services/signaling/pb_user_id.dart`, `docs/POCKETBASE_SETUP.md`).
- Symmetric `creatorUuid` в исходящих signaling payload'ах (коммит `58d2049`).
- Incoming-call auth race зафиксирована (коммит `ae47280`).
- **Решено**: PocketBase для address-book discovery **не используется**. Контактный discovery остаётся через bundle exchange (privacy-first; никаких public directory metadata).

### Bootstrap + конфигурация

- Env-конфиг: committed `.env.defaults` (asset), runtime override через `--dart-define=<KEY>=value`. `.env` остаётся в `.gitignore` и больше не входит в asset bundle.
- Структурированное логирование через `client/lib/logging/logger.dart` (`Logger.debug/info/warn/error`) с auto-redaction sensitive ids выше DEBUG уровня. Прямой `print()` в `lib/` запрещён (project rule + regression test `client/test/security/private_key_no_export_test.dart`).
- Сенситивные ключи проходят через `StorageService` (regression-gated by `secure_storage_policy_test.dart`).
- `client/lib/crypto/ratchet_service.dart` doc-comment честно отражает фактическую крипто-модель (symmetric KDF chain on top of X25519 shared secret, no DH ratchet, no PFS) — закрыло рекомендацию #3 из `post-pocketbase-hardening.md`.

### Quality gates

- `flutter pub get` / `flutter analyze` / `flutter test` — все запускаются локально и в CI.
- CI quality gate (`.github/workflows/ci.yml`): analyze + test + build web + build apk + optional signaling smoke. (Если `build-apk` job показывает `if: false`, см. ROADMAP.md M-chore для статуса re-enable.)

### Дизайн-система v2

- Apple Liquid design layer (`client/lib/themes/apple_liquid/`) — tokens, primitives, signature effects (ScanlineOverlay, GrainOverlay, ChromaticAberration, DecryptText, key-fingerprint backdrop), `GlassPageRoute`, `StealthHaptics`, design feedback widgets.
- Geist + Geist Mono bundled (SIL OFL 1.1) под `client/assets/fonts/`.
- `docs/design-system.md` — source of truth для tokens, signature elements, dual-identity, performance discipline, accessibility contract.
- `docs/design-mockups/` — visual HTML companion (8 files, no build step).

(Note: actively being merged via PR #3 at the time of this writing; once sealed, M10 in ROADMAP.md flips to `[x]`.)

## Решённые открытые вопросы

- **Q:** Нужен ли PocketBase для address-book discovery? **A:** Нет — оставляем строго signaling-only. Discovery через bundle exchange.

## Active follow-ups

Tracked in [`.ai-factory/ROADMAP.md`](../.ai-factory/ROADMAP.md):

- M11 — Web rollout readiness (font subsetting, web perf gates, manual web smoke)
- M12 — Two-device manual QA program
- M13 — Appium suite sync (out-of-repo)
- M14 — TURN/relay reliability
- M15 — DH Double Ratchet (PFS upgrade) — future-work, blocked on prerequisites
- M16 — Riverpod DI + secure-storage refactor — prerequisite: M10 merge
