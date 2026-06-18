# Implementation Plan: Reconcile feature/auto-contacts-user-directory в main

Branch: main
Created: 2026-06-14

## Settings
- Testing: yes (проверить существующие тесты)
- Logging: verbose
- Docs: yes (mandatory checkpoint)

## Roadmap Linkage
Milestone: "M17 — Auto-contacts, presence & user directory"
Rationale: Reconciliation feature branch с main после diverged изменений

## Context
Все 10 задач плана `feature-auto-contacts-user-directory.md` уже реализованы в main (commit `7e628fb`). Файлы присутствуют:
- `client/lib/services/user_directory/presence_service.dart`
- `client/lib/services/user_directory/user_directory_service.dart`
- `client/lib/ui/sheets/user_detail_sheet.dart`
- `client/lib/ui/screens/contacts_screen.dart` — расширен presence-логикой
- `client/lib/themes/apple_liquid/widgets/contacts/contact_tile.dart` — online-индикатор
- `client/lib/services/contacts/contact_service.dart` — addOrUpdateContact
- `client/lib/local_app_service.dart` — _publishOwnProfile, startPBBasedWorkers, logout
- `client/lib/main.dart` — вызов startPBBasedWorkers

## Diff summary (main vs feature branch)
- feature branch **без** `DiagnosticsService` и `createDiagnostics()` (main новее)
- feature branch имеет `@visibleForTesting` конструктор в PresenceService (main уже имеет)
- main имеет все методы и фичи из плана

## Tasks

### Phase 1: Verification
- [ ] Task 1: Проверить `PresenceService` — сравнить методы с планом (start, startHeartbeat, setOnline, setOffline, dispose, onPresenceChange, _subscribe, _scheduleReconnect, AppLifecycleListener). Файл: `client/lib/services/user_directory/presence_service.dart`
- [ ] Task 2: Проверить `UserDirectoryService` — fetchAllProfiles, syncToLocalContacts, getCachedProfiles, clearCache, onPresenceChange подписка. Файл: `client/lib/services/user_directory/user_directory_service.dart`
- [ ] Task 3: Проверить `ContactService.addOrUpdateContact` — upsert existing/new, auto_populated, защита ручного nickname. Файл: `client/lib/services/contacts/contact_service.dart`
- [ ] Task 4: Проверить `LocalAppService` — _publishOwnProfile, _upsertProfile, startPBBasedWorkers, logout extensions. Файл: `client/lib/local_app_service.dart`
- [ ] Task 5: Проверить `main.dart` — вызов startPBBasedWorkers в _initializeApp. Файл: `client/lib/main.dart`

### Phase 2: UI Verification
- [ ] Task 6: Проверить `ContactTile` — isOnline параметр, зелёная/серая точка, AnimatedOpacity, Semantics. Файл: `client/lib/themes/apple_liquid/widgets/contacts/contact_tile.dart`
- [ ] Task 7: Проверить `user_detail_sheet.dart` — все секции (user info, device, app, activity), кнопки действий, GlassContainer. Файл: `client/lib/ui/sheets/user_detail_sheet.dart`
- [ ] Task 8: Проверить `ContactsScreen` — _subscribeToPresence, merge cached profiles, auto_populated отображение, search, long-press info. Файл: `client/lib/ui/screens/contacts_screen.dart`

### Phase 3: Tests & Docs
- [ ] Task 9: Проверить и запустить тесты — presence_service_test, user_directory_service_test, contact_tile_test, contacts_screen_test. Файлы: `client/test/services/user_directory/*`, `client/test/ui/contact_tile_test.dart`, `client/test/ui/contacts_screen_test.dart`
- [ ] Task 10: Docs checkpoint — проверить ARCHITECTURE.md, POCKETBASE_SETUP.md на актуальность. Файлы: `docs/ARCHITECTURE.md`, `docs/POCKETBASE_SETUP.md`

## Commit Plan
- **Commit 1** (after tasks 1-8): "chore: verify feature/auto-contacts-user-directory reconciliation on main"
- **Commit 2** (after tasks 9-10): "chore: add tests and docs checkpoint for reconciliation"
