# Performance Benchmarks + Monitoring Dashboard

**Branch:** main (no branch)
**Created:** 2026-06-13
**Type:** Enhancement

## Description

Создать систему performance benchmarks и мониторинг-экран для Stealth Messenger:
- Сбор информации об устройстве (device_info_plus, package_info_plus)
- Генерация и сохранение device ID + счётчик установок
- Эталонные тесты FPS и размера бандла
- API статистики P2P-подключений
- Экран "Мониторинг" с автрообновлением (3 сек):
  - Раздел статистики (чаты, контакты, сообщения, звонки)
  - Раздел устройства (платформа, версия, OS, бренд, ID, число запусков)
  - Раздел P2P/WebRTC (статус, кол-во подключений/каналов)

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
  - `client/lib/services/device/device_info_service_web.dart` — web: user-agent parsing
  - `client/lib/services/device/device_info_service_io.dart` → renamed to `device_info_service_native_impl.dart`
  - `client/lib/services/device/device_info_service_stub.dart` — fallback stub
- [x] Error handling: graceful fallback with `Logger.warn` if `device_info_plus` fails on native
- Files:
  - `client/lib/services/device/device_info.dart` — shared model
  - `client/lib/services/device/device_info_service.dart`
  - `client/lib/services/device/device_info_service_web.dart`
  - `client/lib/services/device/device_info_service_native_impl.dart`
  - `client/lib/services/device/device_info_service_stub.dart`
- Logging: Logger.debug on platform detection, Logger.warn on failure
- Depends on: Task 1

#### Task 3: Create DeviceInfoService test

- [x] Create `client/test/services/device_info_service_test.dart`
- [x] Test `DeviceInfo` model construction (default + provided values)
- [x] Test `DeviceInfoService` singleton instance
- [x] Test graceful fallback via mock `package_info_plus` method channel
- [x] Test `getDeviceInfo()` returns a valid `DeviceInfo` even when device_info_plus unavailable
- Files: `client/test/services/device_info_service_test.dart`
- Depends on: Task 2

#### Task 4: Generate and persist device ID + install tracking

- [x] Create `client/lib/services/device/device_registry_service.dart`
- [x] Generate UUID v4 device ID on first launch (uses `package:uuid`)
- [x] Persist via `StorageService`
- [x] Track `installCount` — increment on each launch
- [x] Expose: `deviceId` (getter), `installCount` (getter), `init()`
- [x] Call `DeviceRegistryService.instance.init()` in main.dart `_initializeApp()`
- Files:
  - `client/lib/services/device/device_registry_service.dart`
  - `client/lib/main.dart`
- Depends on: Task 1

#### Task 5: Extend DashboardService with device fields

- [x] Update `client/lib/services/dashboard/dashboard_service.dart`
- [x] `getDashboardSummary()` now also returns:
  - `deviceId` (truncated)
  - `installCount` (int)
  - `platformType` (string)
  - `osVersion` (string)
  - `deviceModel` (string)
  - `deviceBrand` (string)
  - `appVersion` (string)
  - `appBuildNumber` (string)
- Files: `client/lib/services/dashboard/dashboard_service.dart`
- Depends on: Task 2, Task 4

### Phase 2: Performance Benchmark Harness

#### Task 6: Create frame timing / FPS benchmark

- [x] Create `client/test/performance/fps_benchmark_test.dart`
- [x] Uses `Stopwatch` + `tester.pump()` to track frame rendering time
- [x] Measures 60 frames, reports min/max/avg frame time + count within 16.67ms budget
- [x] Uses `tester.binding.setSurfaceSize()` for consistent resolution
- [x] Renders a representative ListView with cards and tiles
- Files: `client/test/performance/fps_benchmark_test.dart`
- Depends on: nothing

#### Task 7: Add bundle size metrics test

- [x] Create `client/test/performance/bundle_metrics_test.dart`
- [x] Reads `build/web/main.dart.js` size (skips if absent)
- [x] Reads APK sizes from `build/app/outputs/flutter-apk/` (skips if absent)
- [x] Web JS bundle threshold: < 5 MB (3390 KB actual)
- Files: `client/test/performance/bundle_metrics_test.dart`
- Depends on: nothing

#### Task 8: Add runtime performance monitoring to P2PService

- [x] Add public API to `client/lib/p2p_service.dart`:
  - `getConnectionStats()` — returns `{totalConnections, openDataChannels, reconnectCount, lastConnectedAt, connectionSummary}`
  - `_reconnectCount` field — increments when channel reopens after previous connection
  - `_lastConnectedAt` field — timestamp of last channel open
- Files: `client/lib/p2p_service.dart`
- Depends on: nothing

### Phase 3: Monitoring Dashboard Page

#### Task 9: Create MonitoringScreen with auto-refresh

- [x] Create `client/lib/ui/screens/monitoring_screen.dart` (single StatefulWidget, not conditional export)
- [x] Scaffold + GlassAppBar(title: 'Мониторинг') + scrollable GlassContainer cards
- [x] Auto-refresh: `Timer.periodic(Duration(seconds: 3))` for stats refresh
- [x] `WidgetsBindingObserver` to pause/resume timer when app backgrounds/foregrounds
- Files: `client/lib/ui/screens/monitoring_screen.dart`
- Depends on: Task 5

#### Task 10: Build Dashboard Stats section

- [x] Section with chat count, contact count, message count, call count
- [x] Uses `DashboardService().getDashboardSummary()`
- Files: built into `monitoring_screen.dart`
- Depends on: Task 9

#### Task 11: Build Device Info section

- [x] Section with platform, OS version, device model, brand, app version, build number, device ID, install count
- [x] Uses `DeviceInfoService` + `DeviceRegistryService`
- Files: built into `monitoring_screen.dart`
- Depends on: Task 2, Task 4, Task 9

#### Task 12: Build P2P/WebRTC Connection Stats section

- [x] Section with connection summary, total connections, open data channels, reconnect count, last connected time
- [x] Uses `P2PService.instance.getConnectionStats()`
- Files: built into `monitoring_screen.dart`
- Depends on: Task 8, Task 9

#### Task 13: Register monitoring screen in navigation

- [x] Add "Open monitoring" button in Settings screen diagnostics card
- [x] Import + navigate via `MaterialPageRoute`
- Files: `client/lib/ui/screens/settings_screen.dart`
- Depends on: Task 9

### Phase 4: CI & Docs

#### Task 14: Add performance tests to CI

- [x] Remove `--no-tree-shake-icons` from `build-web` job in `.github/workflows/ci.yml`
- [x] Performance tests auto-included via blanket `flutter test test/` call
- Files: `.github/workflows/ci.yml`
- Depends on: Task 6, Task 7

#### Task 15: Documentation checkpoint

- [x] Plan updated with completion status and actual build outcomes
- [x] `ROADMAP.md` milestone M11 updated (handled below)
- Files: `.ai-factory/plans/perf-benchmarks-monitoring.md`
- Depends on: all previous tasks

## Commit Plan

| # | Tasks | Commit Message |
|---|-------|----------------|
| 1 | 1, 2, 3, 4 | `feat(device): add DeviceInfoService, DeviceRegistryService, device_id + install tracking` |
| 2 | 5, 6, 7, 8 | `feat(perf): add FPS benchmark, bundle metrics, P2P connection stats, extend DashboardService` |
| 3 | 9, 10, 11, 12, 13 | `feat(ui): add MonitoringScreen with auto-refresh, stats, device info, P2P/WebRTC sections` |
| 4 | 14, 15 | `ci: remove --no-tree-shake-icons, add perf tests to CI` |
