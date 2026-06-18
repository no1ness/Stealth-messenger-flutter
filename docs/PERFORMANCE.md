[← Design System](design-system.md) · [Back to README](../README.md) · [Security →](SECURITY.md)

# Performance Optimisation — M18

## Baseline Problems

| Layer | Issue | Impact |
|---|---|---|
| UI/main thread | `chats_screen.dart` — 28 state fields, `setState()` rebuilds entire tree; search recomputed on every build | Unnecessary rebuilds at every keystroke / unrelated state change |
| UI/paint | `BackdropFilter(blur: 10)` ×3 per outgoing bubble, 320 `canvas.drawLine` per bubble via `ScanlineOverlay` | GPU drop during scroll in long lists |
| Data | `getMessages()` returns ALL messages — in-memory pagination (skip/take); `fetchLastMessage` loads 1000 rows | Freezes when opening chat with 1000+ messages |
| Crypto | AES-GCM + X25519 sequential `await` on main isolate — 40+ decrypts = ~20ms main isolate time | Micro-freezes when loading messages |
| Pattern | `ContactService.getNicknameForUser()` loads ALL contacts per call; `_getOtherUserId()` per-message chat lookup | Quadratic complexity O(n·m) |
| Memory | `LocalAppService()` — 16 call sites, each creates a new instance with workers; `StreamController` not closed | Memory leaks, duplicate workers |
| Architecture | Singleton was missing in `LocalAppService`, StreamControllers leaked | Accumulated resource waste |

## Implemented Optimisations

### Phase 1 — UI Quick Wins

| Task | Change | Expected Improvement |
|---|---|---|
| T1 | Search results cached in state fields (`_filteredChats`/`_filteredMessages`); 200ms debounce on message search; 500ms debounce on `_loadChats()` | `setState` ≤ 3 calls/sec on fast typing; no rebuild on unrelated state changes |
| T2 | `InsightPanel` widget plugged (was already extracted but unused); search bar extracted into `ChatSearchBar` widget with its own Timer | Smaller rebuild surface in `chats_screen.dart` |

### Phase 2 — Data Layer

| Task | Change | Expected Improvement |
|---|---|---|
| T3 | `getMessages(chatId, {limit, offset})` in DB layer stops after `limit` rows (no full scan + decrypt); `getLastMessage()` returns 1 row via `prev` cursor direction | Initial render < 5ms (from ~150ms) for 2000-message chat |
| T4 | `_getOtherUserId()` / `_isGroupChat()` — in-memory cache per chatId; `getNicknamesBatch()` / `getOtherPublicKeysBatch()` — one `getContacts()` call per batch | 0 per-message DB queries for 50-message batch |
| T5 | `CryptoIsolateService.decryptBatch()` — batch AES-GCM decryption via `compute()` (background isolate) for ≥3 items; fall-through to main thread for 1–2 items | UI stays at 60fps during bulk decrypt |

### Phase 3 — GPU / Shaders

| Task | Change | Expected Improvement |
|---|---|---|
| T6 | `_ScanlinePainter` — `Picture` cache: paint once, reuse via `drawPicture()` | 1 `drawPicture` per bubble instead of 320 `drawLine` |
| T7 | BackdropFilter sigma: bubble body 10→6, input bar 20→8, attachment bar 10→6 | 1 BackdropFilter per bubble (was 3), GPU < 1ms total |
| T8 | `ChromaticAberration.ghostBuilder` enabled on all platforms (was `kIsWeb` only) | No duplicate full child build on mobile during focus animation |

### Phase 4 — Architecture

| Task | Change | Expected Improvement |
|---|---|---|
| T10 | `LocalAppService` — singleton (factory pattern), `init()` extracted, `_kickoffBackgroundWorkers()` guarded | `identical(instance, instance2)` → `true`; workers run exactly once |
| T11 | `P2PService.dispose()` closes all connections + `_messageController`; `P2PDiscoveryService.stop()` closes `_peerController` | Zero `StreamController` leaks |

### Phase 5 — Startup

| Task | Change | Expected Improvement |
|---|---|---|
| T12 | `DeviceRegistryService.init()` + `startPBBasedWorkers()` deferred to `addPostFrameCallback`; `ThemeController.loadInitial()` awaited on critical path | Cold start first frame < 200ms (from ~1000–2000ms) |

## Deferred (Phase 6 — Low Priority)

- ChatListPanel swap (7 blockers unresolved)
- PresenceService heartbeat event model (timer lifecycle already clean)
- CircuitBoardBackground canvas cache
- DecryptText AnimatedBuilder
- Benchmark gates (test files)

## See Also

- [Design System](design-system.md) — дизайн-токены и UI-компоненты
- [Architecture](ARCHITECTURE.md) — обзор системы
- [Deployment](deployment.md) — деплой и CI/CD
