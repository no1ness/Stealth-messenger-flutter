# Implementation Plan: One-Button App Updates

Branch: `feature/diagnostics-logs-screen` (plan created without branch switch because the worktree already has unrelated local changes)
Created: 2026-06-10
Mode: full (no `--parallel`)

## Goal

Добавить простую систему обновления приложения без Play Store / App Store:

- при запуске показывать текущую версию приложения;
- при запуске проверять доступность новой версии и показывать update prompt, если обновление доступно;
- пользователь нажимает одну кнопку, приложение скачивает обновление и передает APK в системный Android package installer;
- в Settings показывать текущую версию и дать ручную кнопку проверки обновления;
- не добавлять облачный backend для пользовательских данных, истории, контактов или вложений.

## Assumptions

- Первый implementation target: Android APK sideload/update flow. В проекте есть Android platform folder; iOS platform отсутствует, web не может устанавливать APK.
- Update source: статический HTTPS manifest, заданный через `.env.defaults` / `--dart-define=APP_UPDATE_MANIFEST_URL=...`. Это не backend для пользовательских данных; это release metadata endpoint.
- Manifest содержит минимум: `version`, `buildNumber`, `apkUrl`, `sha256`, `mandatory`, `releaseNotes`.
- Установка APK выполняется через Android package installer после явного действия пользователя. Silent install не планируется.
- UI strings остаются на английском, как текущий Settings UI (`Settings`, `Privacy & security`, `Open diagnostics & logs`).

## Settings

- Testing: yes
- Logging: verbose
- Docs: yes

Logger API: использовать только `Logger.{debug,info,warn,error}(String message, {Map<String,dynamic>? extras})`. Никаких `tag` параметров, `print()` или `debugPrint()` в `client/lib/`.

## Roadmap Linkage

Milestone: "none"
Rationale: Skipped by user/default; app updates are not currently represented as an active ROADMAP milestone and should be promoted through `$aif-roadmap` separately if needed.

## Research Context

Source: `.ai-factory/RESEARCH.md` (Active Summary)

Active summary is about the future Double Ratchet crypto upgrade and does not apply to this update/version feature.

## Existing Context

- `client/pubspec.yaml` already defines app version: `0.1.0+1`.
- `package_info_plus` is already present and used by `client/lib/services/diagnostics/app_environment_info.dart`.
- Visible Settings version display does not exist yet.
- `client/lib/main.dart` owns startup bootstrap and currently shows only loading, startup error, `MainTabs`, or registration.
- `client/lib/ui/screens/settings_screen.dart` owns Settings cards and already has diagnostics navigation and refresh patterns.
- `url_launcher` exists, but direct install of a downloaded APK needs Android platform wiring, not just opening a URL.
- Project rule forbids new cloud backend for contacts/messages/attachments/call history. Static update metadata is allowed only for release delivery metadata.

## Commit Plan

- **Commit 1** (after tasks 1-3): `feat(update): add update metadata and android install bridge`
- **Commit 2** (after tasks 4-6): `feat(update): wire startup prompt and settings version UI`
- **Commit 3** (after tasks 7-8): `test(update): cover update service and UI flows`
- **Commit 4** (after task 9): `docs(update): document sideload update flow`

## Tasks

### Phase 1: Update Metadata And Service Core

- [x] **Task 1: Add app update models and version comparison helpers**
  - Deliverable: create `client/lib/services/app_update/app_update_models.dart` with immutable models for current version, remote update manifest, update status, and download/install state. Add pure version/build comparison helpers that handle semver-like `version` and integer `buildNumber`.
  - Expected behavior: service code can determine `upToDate`, `optionalUpdateAvailable`, `mandatoryUpdateAvailable`, `unsupportedPlatform`, and `checkFailed` without UI logic.
  - Files: `client/lib/services/app_update/app_update_models.dart`, `client/test/services/app_update/app_update_models_test.dart`.
  - Logging requirements: pure helpers should not log; any parse failure surfaced to callers must carry enough context for caller logs. Tests should verify invalid input is rejected or downgraded deterministically.
  - Dependencies: none.

- [x] **Task 2: Implement manifest fetch and update check service with provider-closure DI**
  - Deliverable: create `client/lib/services/app_update/app_update_service.dart` that reads current app version via an injected provider defaulting to `PackageInfo.fromPlatform()`, fetches a static HTTPS manifest URL, parses manifest JSON, compares versions, and returns an update status.
  - Expected behavior: if `APP_UPDATE_MANIFEST_URL` is absent, startup/settings report `notConfigured` without failing app startup. Network, parse, or checksum metadata errors degrade to `checkFailed` and never block registration/chat flows unless a successfully parsed manifest marks an update mandatory.
  - Files: `client/lib/services/app_update/app_update_service.dart`, `client/lib/main.dart` for adding `APP_UPDATE_MANIFEST_URL` to `_kDartDefineEnvKeys`, `client/.env.defaults` if the key list/header exists there.
  - Logging requirements: `Logger.debug('[app-update] check started', extras: {'source': 'startup|settings'})`; `Logger.info('[app-update] update status resolved', extras: {'status': status.name, 'currentVersion': current.display, 'latestVersion': latest?.display})`; `Logger.warn('[app-update] manifest unavailable', extras: {'error': error})`; do not log signed URLs with query tokens, only host/path or configured/not-configured state.
  - Dependencies: Task 1.

- [x] **Task 3: Add Android download, checksum verification, and package-installer bridge**
  - Deliverable: add Android-only update installer that downloads the APK to app cache, verifies SHA-256 from manifest, exposes progress, and invokes the Android package installer through a small platform channel plus FileProvider-safe URI handling.
  - Expected behavior: on Android, one button starts download and opens the installer. On web/non-Android, service returns `unsupportedPlatform` and UI shows a clear non-installable state. Silent install is explicitly not attempted.
  - Files: `client/lib/services/app_update/app_update_installer.dart`, `client/android/app/src/main/kotlin/.../MainActivity.kt` or current Android host file, `client/android/app/src/main/AndroidManifest.xml`, `client/android/app/src/main/res/xml/update_file_paths.xml` if FileProvider paths are needed, `client/pubspec.yaml` only if a minimal download/path dependency is required.
  - Logging requirements: `Logger.info('[app-update] download started', extras: {'bytesExpected': total})`; `Logger.debug('[app-update] download progress', extras: {'received': received, 'total': total})`; `Logger.info('[app-update] checksum verified')`; `Logger.error('[app-update] install handoff failed', extras: {'error': error})`. Never log full local file contents or sensitive URLs.
  - Dependencies: Task 2.

### Phase 2: Startup UX And Settings Integration

- [x] **Task 4: Show app version during startup/loading**
  - Deliverable: update startup loading UI in `client/lib/main.dart` to display app name and current version/build while initialization runs, using the same package metadata source or `AppEnvironmentInfo`-compatible helper.
  - Expected behavior: the loading screen displays `Stealth <version>+<build>` when available and `Stealth version unknown` if package metadata fails. Startup must not fail because package metadata is unavailable in tests.
  - Files: `client/lib/main.dart`, optional shared helper in `client/lib/services/app_metadata/app_metadata_service.dart` if needed to avoid duplicating diagnostics code.
  - Logging requirements: `Logger.debug('[bootstrap] app version loaded', extras: {'version': displayVersion})`; `Logger.warn('[bootstrap] app version unavailable', extras: {'error': error})` on fallback.
  - Dependencies: Task 2 if using shared metadata provider; otherwise can run after Task 1.

- [x] **Task 5: Add startup update prompt**
  - Deliverable: update `_MyAppState._initializeApp()` in `client/lib/main.dart` to run a non-fatal update check after env loading and before final home selection, then show a dedicated update prompt when a new version is available.
  - Expected behavior: optional update shows a dismissible prompt with release notes, current/latest version, and one primary button `Update now`; mandatory update removes/blocks the skip action. If check fails or is not configured, app continues normally and logs the condition.
  - Files: `client/lib/main.dart`, new `client/lib/ui/screens/app_update/update_prompt_screen.dart` or private widget near startup if small.
  - Logging requirements: `Logger.info('[app-update.ui] prompt shown', extras: {'mandatory': mandatory, 'currentVersion': current.display, 'latestVersion': latest.display})`; `Logger.debug('[app-update.ui] user skipped optional update')`; `Logger.info('[app-update.ui] update button pressed')`; `Logger.error('[app-update.ui] update flow failed', extras: {'error': error})`.
  - Dependencies: Tasks 2 and 3.

- [x] **Task 6: Add Settings version and manual update controls**
  - Deliverable: extend `client/lib/ui/screens/settings_screen.dart` with an `App` or `Updates` card that shows current version/build and update status, plus a manual `Check for updates` / `Update now` button when applicable. Add accessibility constants only for automation-facing controls.
  - Expected behavior: Settings displays app version even when update manifest is not configured; manual check reuses the same service and installer as startup; UI follows existing `GlassContainer`, `OutlinedButton.icon`, `FilledButton.icon`, `AppSpacing`, and `AppTypography` patterns. Navigation must use `MaterialPageRoute` if a separate screen is introduced.
  - Files: `client/lib/ui/screens/settings_screen.dart`, `client/lib/constants/accessibility_ids.dart` if adding semantics labels, optional `client/lib/ui/screens/app_update/update_status_widgets.dart` if the widget grows too large.
  - Logging requirements: `Logger.debug('[settings.ui] update check requested')`; `Logger.info('[settings.ui] update status displayed', extras: {'status': status.name})`; `Logger.info('[settings.ui] update install requested')`; `Logger.warn('[settings.ui] update unavailable or unsupported', extras: {'reason': status.name})`.
  - Dependencies: Tasks 2 and 3.

### Phase 3: Tests And Regression Gates

- [x] **Task 7: Add service and installer tests with fake providers**
  - Deliverable: add unit tests for update manifest parsing, version comparison, check failure fallback, not-configured state, mandatory vs optional update, checksum mismatch, and unsupported platform behavior.
  - Expected behavior: tests do not perform real network, package-info, filesystem, or Android installer calls; use provider closures and fake download/install functions.
  - Files: `client/test/services/app_update/app_update_service_test.dart`, `client/test/services/app_update/app_update_installer_test.dart`, `client/test/services/app_update/app_update_models_test.dart`.
  - Logging requirements: tests may assert critical log-free behavior indirectly by ensuring no thrown exceptions on failure paths; production code logs via `[app-update]` prefixes only.
  - Dependencies: Tasks 1-3.

- [x] **Task 8: Add widget tests for startup prompt and settings version/update UI**
  - Deliverable: add widget tests for optional update prompt, mandatory update prompt, update button callback, version fallback, and Settings version/update card rendering. If `SettingsScreen` is too hard to test because it constructs `LocalAppService`, introduce the smallest constructor injection needed for app metadata/update providers.
  - Expected behavior: tests wrap widgets in `MaterialApp`, use fake update status providers, avoid `pumpAndSettle()` when animations/timers run, and verify accessible labels if added.
  - Files: `client/test/ui/screens/app_update/update_prompt_screen_test.dart`, `client/test/ui/screens/settings_screen_update_test.dart` or equivalent existing test location.
  - Logging requirements: UI callbacks should emit the `[app-update.ui]` / `[settings.ui]` logs from Tasks 5-6; tests should not introduce `print()`/`debugPrint()`.
  - Dependencies: Tasks 5 and 6.

### Phase 4: Documentation And Verification

- [x] **Task 9: Document update manifest, release process, and manual verification**
  - Deliverable: add documentation for preparing a release APK, publishing the static manifest, required HTTPS hosting, checksum generation, Android install permissions/user flow, and how version/build is displayed.
  - Expected behavior: docs explicitly state that Play/App Store APIs are not used, silent install is not supported, and update metadata is not a user-data backend.
  - Files: `docs/app-updates.md`, `.ai-factory/DESCRIPTION.md` if implementation adds durable architecture context or key files.
  - Logging requirements: docs must mention expected log prefixes `[app-update]`, `[app-update.ui]`, and `[settings.ui]`, plus how to increase verbosity with `--dart-define=STEALTH_LOG_LEVEL=debug`.
  - Dependencies: Tasks 1-8.

## Dependency Graph

```text
1 ──► 2 ──► 3 ──► 5 ──► 8 ──► 9
      │      └────► 6 ──► 8
      └────► 4
1 ───────────────► 7
2 ───────────────► 7
3 ───────────────► 7
```

## Definition of Done

- [ ] Startup loading UI shows app version/build or an explicit fallback.
- [ ] Startup update check does not break normal app launch when manifest is absent/unreachable.
- [ ] Optional update prompt can be dismissed; mandatory update cannot be skipped.
- [ ] Android `Update now` downloads APK, verifies SHA-256, and opens system package installer.
- [ ] Settings shows current version/build and supports manual update check.
- [ ] Non-Android platforms show unsupported/not-configured state instead of failing.
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes, including update service and UI tests.
- [ ] `client/test/security/no_bare_logging_test.dart` passes.
- [ ] `docs/app-updates.md` documents release/update operations.

## Out of Scope

- Play Store / App Store / TestFlight update APIs.
- Silent background installation.
- iOS update implementation.
- Auto-update for web/PWA deployments.
- New backend for user data, message history, contacts, attachments, call history, or analytics.
- Cryptographic Double Ratchet work from `.ai-factory/RESEARCH.md`.
