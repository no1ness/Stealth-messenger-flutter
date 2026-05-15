# Call Screens Controller-Pattern Split (P5.2 + P5.3 follow-up)

**Branch:** TBD — `feature/call-screens-controller-split`, отрезать **от `main`** после merge `feature/pocketbase-signaling`. До merge план существует только как документ; ветка не создаётся.
**Created:** 2026-05-14
**Slug:** `call-screens-controller-split`
**Source plan:** `.ai-factory/plans/post-pocketbase-hardening.md` (P5.2 / P5.3, deferred)

## Settings

- **Testing:** yes — новые unit-тесты для controller state transitions, существующие semantics-тесты должны проходить без модификаций.
- **Logging:** verbose — DEBUG-логи на ключевых state-переходах controller (idle → connecting → connected → disconnected) через `Logger` из P4.
- **Docs:** no — это рефакторинг, документация уже отражает архитектуру (`DESCRIPTION.md` обновлён).

## Roadmap Linkage

- **Milestone:** none
- **Rationale:** ROADMAP.md не существует. `/aif-verify --strict` должен сообщать WARN, не fail.

## Зачем

`webrtc_call_screen_native_impl.dart` (994 строк) и `webrtc_call_screen_web.dart` (1144 строк) — крупнейшие оставшиеся UI-монолиты. Каждый держит в одном `State<WebRTCCallScreen>` пять разнородных ответственностей:

1. WebRTC peer connection + media (tracks, streams, audio routing)
2. PocketBase signaling wiring (`offer/answer/candidate/hangup` через `WebRtcSignalingService`)
3. UI state (mute/speaker/camera/timer)
4. Lifecycle (initState/dispose, таймеры reconnect)
5. View tree (~200-280 строк `build()`)

Это усложняет review (любое изменение в одной оси задевает все), мешает unit-тестировать поведение без `flutter_webrtc`, и блокирует переиспользование call-логики (например, picture-in-picture или групповые звонки в будущем).

Цель — controller-pattern: state и lifecycle живут в platform-specific Controller, media-плумбинг — в MediaBindings, View остаётся тонким `StatefulWidget`-слоем который только биндит controller на UI и слушает его notifier.

## Источники-контракты

- **Публичный API `WebRTCCallScreen`** не меняется: `peerName`, `chatId`, `isCaller`, `isVideoCall`, `initialOffer`, `callerUserId`.
- **Accessibility ids** (`AccessibilityIds`) сохраняются 1:1.
- **`webrtc_call_screen_semantics_test.dart`** должен проходить без модификаций (Hang up / Mute / Speaker / Call status labels).
- **Logger usage** (P4): controller использует `Logger.info/warn/error` под scope `[stealth-call]` с redaction sensitive ids.
- **PocketBase identity** (P1): controller передаёт raw local UUID в `WebRtcSignalingService` — трансформация в PB-id делается внутри signaling layer (см. `pb_user_id.dart`).

## Target shape

После split (per file):

```
client/lib/ui/screens/calls/
  ├── native_call_controller.dart       (~350 строк)
  ├── native_call_media_bindings.dart   (~400 строк)
  └── (view остаётся в webrtc_call_screen_native_impl.dart, ~250 строк)

  ├── web_call_controller.dart          (~400 строк)
  ├── web_call_media_bindings.dart      (~450 строк)
  └── (view остаётся в webrtc_call_screen_web.dart, ~300 строк)
```

Целевой размер модуля — до ~500 строк. View-слой не превышает 300 строк (build + helper builders).

## Phase 1 — Native call screen split ✅ done

**Файл-источник:** `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`
**Target line count after:** ~250.
**Shipped:** commit `a1231cf` — `refactor(ui): split webrtc_call_screen_native_impl into controller/media/view`.

### Task 1.1 — Extract `NativeCallController`

- **Файл:** `client/lib/ui/screens/calls/native_call_controller.dart` (новый).
- **Класс:** `NativeCallController extends ChangeNotifier` (или `ValueNotifier<NativeCallState>` если state-объект достаточно мал).
- **State fields переносятся из `_WebRTCCallScreenState`:**
  - `WebRtcSignalingService? _signaling`
  - `String? _targetUserId`, `String? _selfUserId`, `String? _activeRoomId`
  - `StreamSubscription<RtcMessage>? _signalingSub`
  - `Timer? _connectionTimeout`, `Timer? _callTimer`
  - `bool _connected`, `bool _closing`, `bool _muted`, `bool _speakerEnabled`, `bool _cameraOff`
  - `int _callDurationSeconds`, `String? _statusMessage`
  - `final List<RTCIceCandidate> _pendingCandidates`
- **Public API:**
  - `Future<void> initialize({required String chatId, required bool isCaller, required bool isVideoCall, Map<String, dynamic>? initialOffer, String? callerUserId})`
  - `Future<void> dispose()` (overrides ChangeNotifier.dispose)
  - `Future<void> hangUp()`
  - `void toggleMicrophone()`
  - `void toggleSpeaker()`
  - `void toggleCamera()`
  - Properties getters для read-only state (`bool get connected`, etc.)
  - `MediaBindings get media` (injected — см. Task 1.2)
- **Methods вынесенные из state:**
  - `_startCall`, `_handleAnswer`, `_handleRemoteCandidate`, `_handleRemoteHangup`
  - `_onSignalingMessage`, `_flushPendingCandidates`
  - `_startTimer`
- **Логи (verbose):** `Logger.info('[stealth-call] controller initialize', extras: {'chatId': chatId, 'isCaller': isCaller})`, `Logger.debug('[stealth-call] state transition', extras: {'from': old, 'to': new})` на каждом state change.
- **Зависимости:** принимает `LocalAppService`, `PeerResolver`, `WebRtcSignalingService.builder` через ctor для testability.

### Task 1.2 — Extract `NativeCallMediaBindings`

- **Файл:** `client/lib/ui/screens/calls/native_call_media_bindings.dart` (новый).
- **Класс:** `NativeCallMediaBindings` — plain class без notifier.
- **Fields:**
  - `RTCPeerConnection? _peerConnection`
  - `MediaStream? _localStream`, `MediaStream? _remoteStream`
  - `RTCVideoRenderer _localRenderer`, `RTCVideoRenderer _remoteRenderer`
  - `Timer? _statsTimer`
- **Methods вынесенные из state:**
  - `createPeerConnection`, `appendTurnServer`, `requestMicrophonePermission`
  - `createLocalStream`, `attachLocalMedia`
  - `attachRemoteStream`, `createOffer`, `applyRemoteOffer`
  - `setMicrophoneMuted(bool)`, `setSpeakerphoneOn(bool)`, `setCameraOff(bool)`, `switchCamera`
  - `applyAudioRouting`
  - `startStatsLogger`, `dispose`
- **Callbacks → controller:**
  - `onRemoteStreamReady(MediaStream)` — controller обновит UI state.
  - `onConnectionStateChanged(RTCIceConnectionState)` — controller решает markConnected vs reconnect.
  - `onLocalCandidate(RTCIceCandidate)` — controller отправит через signaling.
- **Логи (verbose):** все `Logger.info('[stealth-call] media ...')` уже мигрированные в P4 остаются.

### Task 1.3 — Reduce widget to view

- **Файл:** `client/lib/ui/screens/webrtc_call_screen_native_impl.dart` (модифицировать).
- **После:** state класс держит только `late NativeCallController _controller;` и подписку на его notifier; `build()` потребляет `_controller.connected`, `_controller.muted`, etc.
- **Удалить из state:** все методы перенесённые в controller/media (Tasks 1.1-1.2).
- **Сохранить в state:**
  - `initState/dispose` — только инициализация controller + dispose.
  - `build()` + helper builders (`_buildControlButton`, `_buildStatusChip`).
  - `_showSnackBar` (UI-only).
  - `_formatDuration` (UI-only helper).
  - `PopScope` обработчик — делегирует `_controller.hangUp()`.
- **Целевой размер:** ~250 строк.

### Task 1.4 — Unit tests для `NativeCallController`

- **Файл:** `client/test/ui/screens/calls/native_call_controller_test.dart` (новый).
- **Кейсы (через fake `WebRtcSignalingService`, fake `MediaBindings`):**
  - `initialize` устанавливает state `connecting`, отправляет offer когда `isCaller=true`.
  - `initialize` применяет `initialOffer` и отправляет answer когда `isCaller=false && initialOffer != null`.
  - Получение `RtcMessageType.answer` после offer → state `connected`.
  - Получение `RtcMessageType.candidate` до `setRemoteDescription` → буферизуется в `_pendingCandidates`.
  - Получение `RtcMessageType.hangup` → controller.dispose() + state `disconnected`.
  - `toggleMicrophone` / `toggleSpeaker` / `toggleCamera` — изменяют state + вызывают media методы.
  - Двойной `hangUp()` идемпотентен.
- **Логи:** не нужны (тест).
- **Blocked by:** Tasks 1.1, 1.2.

**Phase 1 commit:** `refactor(ui): split webrtc_call_screen_native_impl into controller/media/view`.

## Phase 2 — Web call screen split ✅ done

**Shipped:** commit `b9df0c1` — `refactor(ui): split webrtc_call_screen_web into controller/media/view`.

Параллельная структура. Отличия от Phase 1:

- Использует `web.HTMLVideoElement` вместо `RTCVideoRenderer` (требует `_registerViewType`, `_initVideoElements`).
- `_playLocalPreview` и `_attachLocalAudio` — web-specific (autoplay policy).
- `_startAudioAudit` вместо `_startStatsLogger` (web stats API другой).

### Task 2.1 — Extract `WebCallController`

- **Файл:** `client/lib/ui/screens/calls/web_call_controller.dart` (новый).
- **API и контракт идентичны `NativeCallController`** (одинаковые публичные методы, одинаковый набор state-полей). Отличие — он принимает `WebCallMediaBindings`, а не Native.
- Это даёт возможность позже завести интерфейс `CallController` если потребуется shared UI слой.

### Task 2.2 — Extract `WebCallMediaBindings`

- **Файл:** `client/lib/ui/screens/calls/web_call_media_bindings.dart` (новый).
- **Дополнительные методы (vs native):** `registerViewType`, `initVideoElements`, `playLocalPreview`, `attachLocalAudio`, `startAudioAudit`.
- **Pencil-edge:** web-specific autoplay handling — не теряем при extraction (часто фиксили).

### Task 2.3 — Reduce widget to view

- **Файл:** `client/lib/ui/screens/webrtc_call_screen_web.dart`.
- **Сохранить:** `_registerViewType` (требует BuildContext + JS interop, остаётся в state), `build()`, helper builders.
- **Целевой размер:** ~300 строк.

### Task 2.4 — Unit tests для `WebCallController`

- **Файл:** `client/test/ui/screens/calls/web_call_controller_test.dart` (новый).
- **Кейсы:** идентичны Task 1.4. Можно поделить общий тестовый helper через mixin/функцию.
- **Blocked by:** Tasks 2.1, 2.2.

**Phase 2 commit:** `refactor(ui): split webrtc_call_screen_web into controller/media/view`.

## Commit Plan

| #   | После задачи | Commit                                                                          | Status                  |
| --- | ------------ | ------------------------------------------------------------------------------- | ----------------------- |
| 1   | 1.1–1.4      | `refactor(ui): split webrtc_call_screen_native_impl into controller/media/view` | ✅ shipped (`a1231cf`) |
| 2   | 2.1–2.4      | `refactor(ui): split webrtc_call_screen_web into controller/media/view`         | ✅ shipped (`b9df0c1`) |

Каждый коммит атомарен: один файл-источник полностью раскладывается на 3 новых файла + соответствующий тест в одном коммите, чтобы CI не падал на промежуточном состоянии.

## Логирование (Verbose policy)

- Каждый state transition в controller → `Logger.debug('[stealth-call] state transition', extras: {'from': ..., 'to': ...})`.
- Сетевые операции (sendOffer/sendAnswer/sendCandidate/hangup) → `Logger.info` на старте, `Logger.warn` на ошибке.
- Media операции (createPeer, attachLocalMedia, attachRemote) → `Logger.info`.
- Audio routing → `Logger.info('[stealth-call] speakerphone', extras: {'enabled': ...})`.
- Никаких raw `print()` — project rule + P7 regression test уже это enforce-ит для private key и линт для print.

## Тестовая стратегия

- **Существующие semantics-тесты** (`webrtc_call_screen_semantics_test.dart`) — НЕ модифицируются. Они должны пройти потому что:
  - Публичный API `WebRTCCallScreen` не меняется.
  - Accessibility ids остаются в одном и том же UI tree.
- **Новые controller unit-тесты** — изолированные, через fakes для `WebRtcSignalingService` и `MediaBindings`. Не требуют `flutter_webrtc` инициализации.
- **Smoke test** (`pocketbase_signaling_smoke_test.dart`) — не затрагивается этим планом.
- **CI** (P2 workflow) на каждом commit прогонит `flutter analyze` + `flutter test`.

## Риски

1. **`flutter_webrtc` API подкапотная разница native vs web.** Mitigation: extraction делается per-platform, общий интерфейс не вводим в первой итерации. Если найдётся хорошая абстракция — выделим её во второй итерации.
2. **State synchronization between Controller и MediaBindings.** Media операции async (await setLocalDescription); controller может попытаться отправить answer до того как media готово. Mitigation: media методы возвращают Future, controller сериализует через `await` цепочку. Уже работает в текущем коде, не теряем при extraction.
3. **Pending ICE candidates буфер.** Если контроллер dispose-ится в момент когда candidates ещё буферизованы — лик. Mitigation: dispose очищает _pendingCandidates.
4. **PopScope handler.** `WillPopScope` / `PopScope` использует `_hangUp` синхронно. После extraction `_controller.hangUp()` тоже sync на entry → safe.

## Чего НЕ делаем

- Не вводим shared `CallController` интерфейс (preliminary abstraction). Если в дальнейшем нужно общее UI поверх native/web, можно extract-нуть из готовых классов после landing.
- Не меняем публичный API `WebRTCCallScreen`.
- Не трогаем `CallManager`, `IncomingCallSignalingService`, `WebRtcSignalingService` — они уже стабилизированы.
- Не переписываем существующие UI элементы (Hang up / Mute / Speaker buttons).

## Pre-merge checklist

- [x] `feature/pocketbase-signaling` смержен в main (открытый PR пройден).
- [x] `git checkout main && git pull && git checkout -b feature/call-screens-controller-split`.
- [x] Запустить `/aif-implement` — два phase-коммита по `commit plan`.
- [x] Локально зелёный (`flutter analyze` — No issues; `flutter test` — 60 passed). CI на ветке: дождаться запуска после push.
- [ ] Ручной smoke: 1-on-1 видео-звонок (web ↔ native) с подключённым PocketBase, чтобы ловить ICE/audio регрессии которые semantics-тесты не покрывают.

## Следующие шаги

После merge текущего PR в main:

```bash
git checkout main && git pull
git checkout -b feature/call-screens-controller-split
/aif-implement @.ai-factory/plans/call-screens-controller-split.md
```
