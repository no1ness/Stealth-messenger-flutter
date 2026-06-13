# Performance Benchmarks + Monitoring Dashboard

**Branch:** main (no branch)
**Created:** 2026-06-13
**Type:** Enhancement

## Description

Создать систему performance benchmarks и веб-страницу мониторинга для Stealth Messenger:
- Измерение FPS, времени загрузки, размера бандла, скорости рендеринга
- Отдельная веб-страница мониторинга со статистикой
- Статистика: пользователи, сообщения, звонки, файлы, установки на устройства, типы/модели устройств

## Settings

- Testing: yes (benchmark tests)
- Logging: verbose
- Docs: yes (mandatory checkpoint at end)

## Roadmap Linkage

**Milestone:** M11 — Web rollout readiness
**Rationale:** Performance benchmarks and monitoring dashboard are prerequisites for web release — provides quantifiable perf gates and visibility into real-world usage across platforms.

## Tasks

### Phase 1: Device Info Infrastructure

#### Task 1: Add device_info_plus and package_info_plus dependencies

- [x] Add `device_info_plus` and `package_info_plus` to `client/pubspec.yaml`
- [x] Run `flutter pub get`
- Files: `client/pubspec.yaml`
- Logging: Logger.debug on dependency resolution
- Depends on: nothing

#### Task 2: Create DeviceInfoService with conditional exports + error handling

- [x] Create platform-conditional files following `StorageService` pattern:
  - `client/lib/services/device/device_info_service.dart` — conditional export
  - `client/lib/services/device/device_info_service_web.dart` — web: user-agent parsing, `kIsWeb`
  - `client/lib/services/device/device_info_service_io.dart` — native: `device_info_plus` API
  - `client/lib/services/device/device_info_service_stub.dart` — fallback stub
- `package_info_plus` works identically on all platforms (no conditional export needed)
- Returns a `DeviceInfo` record/class with:
  - `platformType` (web/android/ios/macos/windows/linux)
  - `osVersion` (string)
  - `deviceModel` (string — browser for web, device model for native)
  - `deviceBrand` (string — manufacturer for native, browser vendor for web)
  - `appVersion` (from package_info_plus)
  - `appBuildNumber` (from package_info_plus)
- Error handling: graceful fallback with `Logger.warn` if `device_info_plus` fails on native
- Files:
  - `client/lib/services/device/device_info_service.dart`
  - `client/lib/services/device/device_info_service_web.dart`
  - `client/lib/services/device/device_info_service_io.dart`
  - `client/lib/services/device/device_info_service_stub.dart`
- Logging: Logger.debug on platform detection, Logger.warn on failure
- Depends on: Task 1

#### Task 3: Create DeviceInfoService test

- Create `client/test/services/device_info_service_test.dart`
- Test platform detection fallback on all platforms
- Test error handling: simulate `device_info_plus` failure, verify graceful fallback
- Test `package_info_plus` integration
- Follow existing service test pattern (`dashboard_service_test.dart`)
- Files: `client/test/services/device_info_service_test.dart`
- Depends on: Task 2

#### Task 4: Generate and persist device ID + install tracking with double-count guard

- Create/update `client/lib/services/device/device_registry_service.dart`
- Generate UUID v4 device ID on first launch (uses `package:uuid` — already in deps)
- Persist via `StorageService` (web: SharedPreferences+IndexedDB, native: flutter_secure_storage)
- Track `firstLaunchAt` (DateTime) timestamp
- Track `installCount` — increment on each launch (read → increment → write)
- Guard against double-count during recovery: add `_firstIncrementDone` flag, check before increment
- In `main.dart` `_initializeApp()`, only increment if not already done this session
- Expose: `getDeviceId()`, `getFirstLaunchAt()`, `getInstallCount()`, `incrementInstallCount()`
- Files:
  - `client/lib/services/device/device_registry_service.dart`
  - Update `client/lib/main.dart` to call increment on startup
- Logging: Logger.debug on device ID generation, Logger.info on install count
- Depends on: Task 1

#### Task 5: Extend DashboardService with device fields

- Update `client/lib/services/dashboard/dashboard_service.dart`
- `getDashboardSummary()` now also returns:
  - `deviceId` (first 8 chars + "...")
  - `installCount` (int)
  - `platform` (string)
  - `appVersion` (string)
  - `deviceModel` (string)
- Keep summary efficient — existing O(n*m) full scan of messages is already measured; device fields are constant-time
- Update `client/lib/local_app_service.dart` facade if needed
- Files:
  - `client/lib/services/dashboard/dashboard_service.dart`
  - `client/lib/local_app_service.dart`
- Logging: Logger.debug on summary aggregation
- Depends on: Task 2, Task 4

### Phase 2: Performance Benchmark Harness

#### Task 6: Create frame timing / FPS benchmark with concrete measurement

- Create `client/test/performance/frame_timing_test.dart`
- Use `Stopwatch` + `tester.pumpFrames()` with known budget (e.g., 2 seconds)
- Manual frame counting via `tester.binding.transientCallbackCount`
- Measures:
  - Average FPS over budget duration
  - Worst frame build time (max between pumpFrames iterations)
  - Number of frames rendered in budget
- Creates a simple benchmark widget with animations (e.g., animated container + glass widget)
- Uses `fake_async` for time control (already a dev dependency)
- Follows pattern from `pumpForGolden()` helper in existing test utils
- Files: `client/test/performance/frame_timing_test.dart`
- Logging: Logger.info with timing results, Logger.debug with raw frame data
- Depends on: nothing

#### Task 7: Add bundle size and build-time metrics (web-first)

- Create `client/test/performance/bundle_metrics_test.dart`
- Web (always available in CI):
  - Run `flutter build web --release`
  - Parse output to extract `main.dart.js` size
  - Measure total build output directory size
  - Measure build duration via Stopwatch around `Process.run()`
- Native APK (optional, skip in CI if no Android SDK):
  - Wrap in try/catch, Logger.warn if tools unavailable
- Store results as structured data (Map with keys, comparable across runs)
- Files: `client/test/performance/bundle_metrics_test.dart`
- Logging: Logger.info with size and duration
- Depends on: nothing

#### Task 8: Add runtime performance monitoring to P2PService

- Add public API to `client/lib/p2p_service.dart`:
  - `activeConnectionCount` getter
  - `getConnectionsSummary()` — returns list of `{chatId, state, iceConnectionState}`
  - Connection state change logging
- Add RTT/latency tracking via DataChannel stats
- Files: `client/lib/p2p_service.dart`
- Logging: Logger.debug on state changes, Logger.info on connection summary
- Depends on: nothing (independent)

### Phase 3: Monitoring Dashboard Page

#### Task 9: Create MonitoringScreen skeleton with auto-refresh

- Create platform-conditional screen files following existing pattern:
  - `client/lib/ui/screens/monitoring_screen.dart` — conditional export
  - `client/lib/ui/screens/monitoring_screen_web.dart` — web implementation
  - `client/lib/ui/screens/monitoring_screen_io.dart` → native impl
  - `client/lib/ui/screens/monitoring_screen_native_impl.dart` — native (mobile) implementation
  - `client/lib/ui/screens/monitoring_screen_stub.dart` — fallback stub
- Basic scaffold: Scaffold + GlassAppBar(title: 'Monitoring') + body (wrapped in `StealthAnimatedBackground` for UI consistency) with scrollable GlassContainer cards
- Auto-refresh: `Timer.periodic(Duration(seconds: 10))` to refresh stats
- `WidgetsBindingObserver` to pause timer when app is backgrounded (follow `settings_screen.dart` pattern)
- Files: all monitoring_screen*.dart files
- Logging: Logger.debug on screen init and timer events
- Depends on: Task 5

#### Task 10: Build Dashboard Stats section

- Inside MonitoringScreen, build cards showing:
  - Chat count, contact count, message count, call count
  - Weekly activity bars (reuse pattern from ProfileScreen)
  - Storage debug: bucket ready, file count
  - Security posture: secure storage ready, keypair status
- Uses `LocalAppService.getDashboardSummary()`, `getWeeklyActivityBars()`, `getStorageDebugSummary()`
- Each metric in a `GlassContainer` card with icon + label + value
- Files: `client/lib/ui/screens/monitoring_screen_web.dart` (and native impl)
- Import patterns from `settings_screen.dart` and `profile_screen.dart`
- Logging: Logger.debug on data load
- Depends on: Task 9

#### Task 11: Build Device Info section with platform icons

- Card showing:
  - Platform (web/android/ios/macos/windows/linux) with platform-specific icon:
    - `Icons.phone_android` (android), `Icons.phone_iphone` (ios), `Icons.laptop` (macos)
    - `Icons.desktop_windows` (windows), `Icons.computer` (linux), `Icons.web` (web)
    - `Icons.devices_other` (fallback)
  - OS version
  - Device model + brand
  - App version + build number
  - Device ID (truncated)
  - Install count
  - First launch date
- Uses `DeviceInfoService` + `DeviceRegistryService`
- Files: `client/lib/ui/screens/monitoring_screen_web.dart` (and native impl)
- Logging: Logger.debug on data load
- Depends on: Task 2, Task 4, Task 9

#### Task 12: Build P2P/WebRTC Connection Stats section with connectivity type

- Card showing:
  - Active P2P connections count
  - Connected chat IDs
  - WebRTC support summary (from `getWebRTCSupport()`)
  - Audio input count
  - ICE connection states (connected/checking/disconnected per chat)
  - Network type (wifi/mobile/ethernet/none) with color-coded indicator:
    - Green for wifi/ethernet, yellow for mobile, red for none
  - Uses `connectivity_plus` — `Connectivity().checkConnectivity()` for initial state and `Connectivity().onConnectivityChanged` stream for live updates
  - Note: on web, `connectivity_plus` v7 reports via browser Network Information API — `ConnectivityResult.ethernet` is desktop-only
- Uses `P2PService.instance` + `getWebRTCSupport()`
- Files: `client/lib/ui/screens/monitoring_screen_web.dart` (and native impl)
- Logging: Logger.debug on stats refresh
- Depends on: Task 8, Task 9

#### Task 13: Register monitoring screen in navigation

- Add a link/button in Settings screen to navigate to MonitoringScreen:
  ```dart
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const MonitoringScreen()),
  );
  ```
- Or add as 5th tab in `main_tabs.dart` (add to `_screens` list + `GlassBottomNavBarItem`)
- Files:
  - `client/lib/ui/screens/settings_screen.dart`
  - OR `client/lib/main_tabs.dart`
- Logging: Logger.debug on navigation
- Depends on: Task 9

### Phase 4: CI & Docs

#### Task 14: Add performance tests to CI

- Update `.github/workflows/ci.yml`:
  - Remove `--no-tree-shake-icons` from the `build-web` job (line 127) — already removed from `build-client-web.sh`, CI must match
  - Add `flutter test --coverage --reporter expanded test/performance/` step
  - Add build-time metric collection to `build-web` job
  - Add benchmark result output to job summary
- Files: `.github/workflows/ci.yml`
- Logging: CI step output
- Depends on: Task 6, Task 7

#### Task 15: Documentation checkpoint

- Update `docs/` with:
  - Performance benchmarks setup and how to run them
  - Monitoring screen usage guide
  - Device info collection privacy notes
- Run `/aif-docs` to update documentation
- Files: `docs/` directory
- Depends on: all previous tasks

## Commit Plan

| # | Tasks | Commit Message |
|---|-------|----------------|
| 1 | 1, 2, 3, 4 | `feat: add device info service + install tracking + test infrastructure` |
| 2 | 5, 6, 7, 8 | `feat: add performance benchmark harness + dashboard service extension` |
| 3 | 9, 10, 11, 12, 13 | `feat: add monitoring dashboard screen with stats, device info, connection stats` |
| 4 | 14, 15 | `ci: add perf tests to CI + documentation checkpoint` |

