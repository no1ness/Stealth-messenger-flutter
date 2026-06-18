# Implementation Plan: Safety-number verification + identity key rotation + CSP

Branch: main
Created: 2026-06-14

## Settings
- Testing: yes
- Logging: verbose
- Docs: yes (mandatory checkpoint)

## Roadmap Linkage
Milestone: "M17 — Auto-contacts, presence & user directory"
Rationale: Security hardening — safety-number verification, key rotation, CSP

## Context
Выборочный перенос функционала из `feature/hardening-di-secure-storage` (11 коммитов, diverged на 43 коммита от main). Без Riverpod/DI — всё на текущих синглтонах.

**Уже есть в main:** `crypto_helper.dart` (все функции), `IdentityService` (базовый), `getSafetyNumber()` в ContactService

## Tasks

### Phase 1: Safety-number verification
- [ ] Task 1: Add `verifyContact(userId)`, `isContactVerified(userId)`, `getContactVerificationStatus()` в `ContactService`. Поля контакта: `verified_at`, `verified_safety_number`. Проверять, что safety-number не изменился с момента верификации. Файл: `client/lib/services/contacts/contact_service.dart`
- [ ] Task 2: Создать `SafetyNumberDialog` — bottom sheet с fingerprint (32-char safety-number), кнопка "Mark as verified". Не использует Riverpod — синглтоны `ContactService`/`IdentityService`. Файл: `client/lib/ui/sheets/safety_number_dialog.dart`
- [ ] Task 3: Интегрировать SafetyNumberDialog в `ContactsScreen` — long-press → "Verify identity". Показывать verification status в ContactTile (✓ verified / ⚠ mismatch). Файлы: `client/lib/ui/screens/contacts_screen.dart`, `client/lib/themes/apple_liquid/widgets/contacts/contact_tile.dart`

### Phase 2: Identity key rotation
- [ ] Task 4: Добавить `rotateIdentityKeypair()` в `IdentityService` — генерирует новый X25519 keypair, сохраняет предыдущий как `privateKey_prev`/`publicKey_prev`/`prev_rotated_at`, обновляет contact bundle. Файл: `client/lib/services/identity/identity_service.dart`
- [ ] Task 5: Добавить prev-key grace fallback в `ContactService.getSafetyNumber()` и `LocalAppService` — если расшифровка новым ключом не удалась, пробовать предыдущий (в течение 24ч grace period). `_prunePrevKey()` для очистки после 24ч. Файлы: `client/lib/local_app_service.dart`, `client/lib/services/contacts/contact_service.dart`
- [ ] Task 6: Добавить кнопку "Rotate keys" в `SettingsScreen` — подтверждение через диалог, после ротации перепубликация профиля в PB (если user_profiles активна). Файл: `client/lib/ui/screens/settings_screen.dart`

### Phase 3: CSP
- [ ] Task 7: Добавить Content-Security-Policy в `<head>` `web/index.html` — `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss: https:; object-src 'none'; base-uri 'self'; frame-ancestors 'none';`. Файл: `client/web/index.html`

### Phase 4: Tests & Docs
- [ ] Task 8: Тесты — `verifyContact` roundtrip, `isContactVerified` после verify, mismatch detection, `rotateIdentityKeypair` генерирует новый ключ и сохраняет prev, grace-period fallback, `_prunePrevKey` очистка. Файлы: `client/test/services/contact_service_test.dart`, `client/test/services/identity_service_test.dart`
- [ ] Task 9: Docs checkpoint — обновить `docs/SECURITY.md` (safety-number flow, key rotation protocol), добавить `docs/web-csp.md` при необходимости. Файлы: `docs/SECURITY.md`, `docs/web-csp.md` (опционально)

## Commit Plan
- **Commit 1** (after tasks 1-3): "feat(security): add safety-number verification UI"
- **Commit 2** (after tasks 4-6): "feat(security): add identity key rotation with grace fallback"
- **Commit 3** (after task 7): "feat(web): add Content-Security-Policy header"
- **Commit 4** (after tasks 8-9): "chore: add tests and docs for security hardening"
