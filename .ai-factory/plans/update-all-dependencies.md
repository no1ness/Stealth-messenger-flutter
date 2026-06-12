# Plan: Update All Dependencies

Branch: `main` (без создания ветки)
Created: 2026-06-11
Mode: full

## Goal

Обновить все зависимости проекта до последних совместимых версий:

- **Flutter/Dart** (client/pubspec.yaml) — 23 прямых + 4 dev зависимости
- **Gradle plugins** (client/android/settings.gradle.kts) — 3 плагина
- **Node.js** (pw-test/package.json) — 2 пакета
- **Docker образы** (server/docker/docker-compose*.yml) — 3 сервиса

## Assumptions

- `flutter pub upgrade --major-versions` — основной инструмент для Flutter-зависимостей
- После обновления прогоняются `flutter analyze` и `flutter test`
- Breaking changes документируются в плане
- Flutter SDK недоступен в текущем окружении WSL — команды выполняются на хосте с Flutter

## Settings

- Testing: yes
- Logging: not applicable (dependency maintenance)
- Docs: yes — breaking changes documented in commit body

## Roadmap Linkage

Milestone: "none"
Rationale: "Skipped by user — dependency maintenance is a recurring chore, not a roadmap milestone"

## Tasks

### Phase 1: Flutter/Dart Dependencies

- [x] **Task 1: Audit current Flutter dependency versions**
  - Deliverable: run `cd client && flutter pub outdated` and record all outdated packages with current → latest version mapping
  - Expected behavior: report lists each dependency with its current constraint, current resolved version, and latest available version
  - Files: `client/pubspec.yaml` (read-only for audit)
  - Logging: N/A — audit output goes to stdout

- [x] **Task 2: Update Flutter dependencies to latest compatible versions**
  - Deliverable: run `cd client && flutter pub upgrade --major-versions` to upgrade all pubspec dependencies to latest compatible versions; review and accept each major version change
  - Expected behavior: pubspec.yaml constraints updated, pubspec.lock regenerated, all packages resolve without conflicts
  - Files: `client/pubspec.yaml`, `client/pubspec.lock`
  - Dependencies: Task 1

- [x] **Task 3: Verify Flutter build and tests pass after upgrade**
  - Deliverable: run `cd client && flutter pub get && flutter analyze && flutter test`
  - Expected behavior: zero analyze errors, all existing tests pass
  - Files: potentially modified source files if API breakages need fixing
  - Dependencies: Task 2

### Phase 2: Gradle/Android Plugins

- [x] **Task 4: Update Gradle plugin versions**
  - Deliverable: update versions in `client/android/settings.gradle.kts`:
    - `com.android.application`: check latest available
    - `org.jetbrains.kotlin.android`: check latest compatible with Flutter
    - `dev.flutter.flutter-plugin-loader`: check latest
  - Expected behavior: `cd client && flutter build apk --debug` compiles successfully (requires Android SDK)
  - Files: `client/android/settings.gradle.kts`
  - Dependencies: none

### Phase 3: Node.js Test Dependencies

- [x] **Task 5: Update Playwright test dependencies**
  - Deliverable: `cd pw-test && npm outdated && npm update`
  - Expected behavior: `playwright` and `webdriverio` updated to latest within semver range; `npm test` still passes
  - Files: `pw-test/package.json`, `pw-test/package-lock.json`
  - Dependencies: none

### Phase 4: Docker/Server Images

- [x] **Task 6: Update Docker service image tags**
  - Deliverable: review and update image tags in `server/docker/docker-compose.yml`:
    - PocketBase: check latest stable tag
    - Caddy: `caddy:2-alpine` — check if newer `2-alpine` exists
    - coturn: `coturn/coturn:latest` — consider pinning to a specific version
  - Expected behavior: `docker compose pull` downloads updated images; `docker compose up -d` starts without errors
  - Files: `server/docker/docker-compose.yml`
  - Dependencies: none

### Phase 5: Verification

- [x] **Task 7: Run full regression suite and document changes**
  - Deliverable:
    1. Run `cd client && flutter analyze && flutter test` (full pass)
    2. Run `cd pw-test && npm test` (if applicable)
    3. Document any breaking changes, deprecated APIs, or migration notes
    4. If any source code changes were required due to API breakages, add logging with `[dep-upgrade]` prefix
  - Expected behavior: all existing functionality preserved; breaking changes documented in commit body
  - Files: any source files modified to fix API breakages, plus commit message
  - Dependencies: Tasks 1-6

## Commit Plan

1. **Task 1-3**: `chore(deps): update Flutter dependencies to latest versions`
2. **Task 4**: `chore(deps): update Android Gradle plugin versions`
3. **Task 5**: `chore(deps): update Playwright test dependencies`
4. **Task 6**: `chore(deps): update Docker service image tags`
5. **Task 7**: `chore(deps): fix API breakages from dependency updates`

## Files to Modify

- `client/pubspec.yaml` — updated version constraints
- `client/pubspec.lock` — regenerated
- `client/android/settings.gradle.kts` — updated plugin versions
- `pw-test/package.json` — updated dependency ranges
- `pw-test/package-lock.json` — regenerated
- `server/docker/docker-compose.yml` — updated image tags
- Potentially source files if API breakages need fixing

## Risks & Considerations

- **Breaking changes**: major version bumps may introduce API incompatibilities; each needs individual review
- **Flutter SDK version**: Flutter SDK 3.x may not support latest package versions; check compatibility before upgrading
- **NDK issue**: Android build currently blocked by malformed NDK at `/usr/lib/android-sdk/ndk/28.2.13676358` — update or fix NDK first
- **No Flutter SDK in WSL**: all Flutter commands must be run on a host with Flutter SDK installed
- **Lockfile stability**: only `crypto: ^3.0.7` was removed previously; verify no unintended promotions in new lockfile

## Definition of Done

- [ ] `cd client && flutter pub get` succeeds
- [ ] `cd client && flutter analyze` passes (zero errors)
- [ ] `cd client && flutter test` passes (all tests)
- [ ] `cd pw-test && npm test` passes (if applicable)
- [ ] `docker compose pull` succeeds for updated images
- [ ] Breaking changes documented in commit body
