# M16 — Riverpod DI Implementation Plan

**Branch:** feature/m16-riverpod
**Status:** PR 1/5 complete (foundation tier)

## Progress

### PR 1 — Foundation tier ✅
- [x] Add `flutter_riverpod: ^2.6.1` to pubspec.yaml
- [x] Create `client/lib/di.dart` with providers:
  - `storageServiceProvider` → `StorageService`
  - `localDatabaseServiceProvider` → `LocalDatabaseService`
  - `localAppServiceProvider` → `LocalAppService`
  - `p2pServiceProvider` → `P2PService`
  - `incomingP2PMessagesProvider` → `StreamProvider<Map>`
- [x] Wrap `main.dart` in `ProviderScope`
- [x] Add provider override tests (3 tests)
- [x] All 315 tests passing

### PR 2 — Identity tier (next)
- [ ] Create `selfUserIdProvider` (reads from StorageService)
- [ ] Migrate screens that use `LocalAppService()` directly:
  - `settings_screen.dart`
  - `chats_screen.dart`
  - `profile_screen.dart`
  - `calls_screen.dart`
  - `contacts_screen.dart`
- [ ] Add provider tests for selfUserId

### PR 3 — Signaling tier
- [ ] Create `pocketBaseClientProvider` (replaces lazy singleton)
- [ ] Remove `resetForTests()` from pocketbase_client.dart
- [ ] Migrate signaling services to use providers

### PR 4 — App services tier
- [ ] Migrate `P2PService` to provider
- [ ] Migrate `P2PDiscoveryService` to provider
- [ ] Update all call sites

### PR 5 — UI listenables
- [ ] Migrate `ThemeController.mode` to `themeModeProvider`
- [ ] Update `ValueListenableBuilder` to `Consumer`

## Files Modified (PR 1)
- `client/pubspec.yaml` — added flutter_riverpod
- `client/lib/di.dart` — new file with providers
- `client/lib/main.dart` — added ProviderScope wrapper
- `client/test/di/providers_test.dart` — new test file

## Test Results
- Flutter tests: 315/315 passing
- Provider tests: 3/3 passing
