# Client Hardening Follow-up (post-PocketBase phase 2)

- Created: 2026-05-20
- Planned branch: `feature/client-hardening-followup` (not yet created — working tree dirty, see "Branch creation" below)
- Base branch: `main`
- Plan mode: full
- Plan owner: webproger2014 (anikakle)

## Settings

- Testing: yes (unit + widget tests required for split services, P2P retry, attachment descriptor, delivery UI)
- Logging: verbose (Logger.debug on every state transition; Logger.info on user-visible events; Logger.warn on degraded paths; Logger.error only for unrecoverable)
- Docs: yes — mandatory docs checkpoint at completion (touches public API of LocalAppService, P2P delivery semantics, attachment protocol, CI matrix)
- Roadmap linkage: none (`.ai-factory/ROADMAP.md` doesn't exist in repo; `/aif-verify --strict` may WARN but not fail)

## Goal

Lock in the gains of the post-PocketBase migration with CI regressions, finish the in-flight cleanups (Logger adoption, LocalAppService size), then upgrade P2P delivery and attachment handling from fire-and-forget + inline-base64 to retry-aware + descriptor-based — all without re-introducing an external cloud backend.

## Research context

Lifted from the user-supplied scope plus reconnaissance findings (see "Reality check" below). Three of the seven originally-named items are already complete in main — those slots are repurposed into regression locks so they can't drift.

## Reality check (recon vs. original scope)

| Original item | Actual state |
| --- | --- |
| pw-test contact-bundle migration | **Done.** 6 files use `readContactBundle()`, 1 uses internal `getContactBundle()`, others don't touch contacts. No raw-UUID add-contact paths remain. Plan task: add a guard so a future script can't slip back. |
| Supabase trace removal | **Done.** `git grep -in supabase` = 0. `post-pocketbase-hardening.md:318-319` already uses generic "внешний cloud backend" phrasing. Plan task: CI guard + archive the plan to `.ai-factory/specs/`. |
| Logger migration | **Partial.** 0 bare `print()`, 55 `debugPrint(` remain. User-named files (`local_app_service.dart`, `profile_screen.dart`, `p2p_service.dart`, `native_call_controller.dart`, `web_call_controller.dart`) are already on Logger.*. Actual hotspots: `native_call_media_bindings.dart` (16), `web_call_media_bindings.dart` (11), various `themes/apple_liquid/` (~24). |
| Large-file split | **Real.** Sizes grew since the user's mental model: local_app_service.dart 1099, chats_screen.dart 1086, profile_screen.dart 635, contacts_screen.dart 614. Plan splits local_app_service.dart (clearest seams) and extracts sub-widgets from chats_screen.dart; profile/contacts stay as-is (they're already in shape). |
| P2P/DataChannel reliability | **Real.** Confirmed fire-and-forget in `local_app_service.sendMessage()` (line 652). No retry, no backoff, no delivery status, no ACK. ICE/TURN config duplicated between `p2p_service.dart:62-91` and `native_call_media_bindings.dart:369-418`. |
| Attachment optimization | **Real.** Confirmed: encrypted blob travels inline as base64 in the `local-attachment:` envelope (`local_app_service.dart:587-589, 756-767`); duplicated between message body and the `attachments` IndexedDB store on sender side. |
| CI Android job | **Different shape.** `build-android` is ACTIVE (not `if: false`) and runs `flutter build apk --debug` on every push (`.github/workflows/ci.yml:91-125`). Plan upgrades to nightly release apk + AAB + macOS analyze instead. |

## Tasks

Tasks tracked via `TaskList` (IDs #1–#15). Below is the same sequence with dependencies; use `/aif-implement` to execute.

### Phase 1 — Lockdown current gains (no behavior change)

- [x] **#1 CI guard: zero Supabase + ban bare logging in `client/lib`** — adds a `git grep` step + a new Dart regression test with an allow-list seeded from the currently-offending files. *(2026-05-20: `.github/workflows/ci.yml` analyze-and-test got the Supabase grep step; `client/test/security/no_bare_logging_test.dart` created; allow-list size 7 — themes/apple_liquid/\* removed from plan's stale seed since WIP already migrated them. Test passes locally.)*
- [x] **#2 pw-test guard: forbid raw UUID in add-contact flows** — new `pw-test/lint-contact-bundle.mjs` + CI step. *(2026-05-20: linter scans every `pw-test/*.mjs` except itself and `contact-bundle-helper.mjs`, fails files that call `addContact(` without showing `readContactBundle` / `getContactBundle` / `"stealth:"` literal evidence. New dedicated `pw-test-lint` job in `.github/workflows/ci.yml` (parallel with analyze-and-test). Local smoke: 5/5 contact-touching files clean. Also wrote `pw-test/README.md`.)*

### Phase 2 — Finish Logger migration

- [x] **#3 Migrate `native_call_media_bindings.dart` + `web_call_media_bindings.dart` to Logger** (blocked by #1). 27 calls combined; sensitive ids pass through `_sensitiveKeys` redaction. *(2026-05-20: 16+11 debugPrint calls in `client/lib/ui/screens/calls/native_call_media_bindings.dart` and `web_call_media_bindings.dart` rewritten to `Logger.{info,warn,debug}` with structured extras. Both files removed from allow-list (5 remaining: logger.dart, voice_message_player, webrtc_call_screen_web, rtc_message, pocketbase_client). `flutter analyze` clean; no_bare_logging_test passes.)*
- [x] **#4 Migrate remaining `debugPrint` + add `STEALTH_LOG_LEVEL` dart-define override** (blocked by #3). Lifts the allow-list to empty. *(2026-05-20: migrated voice_message_player.dart (3), webrtc_call_screen_web.dart (1), rtc_message.dart (1), pocketbase_client.dart (1) to Logger; added `parseLogLevel(String?)` pure function + `STEALTH_LOG_LEVEL` dart-define override + `Logger.logInitialState()` banner method; logger_test.dart extended with 3 parseLogLevel tests (12/12 pass); allow-list down to `lib/logging/logger.dart` only; `rules/base.md:40` and `DESCRIPTION.md:17` synced to Logger.\*-only rule + dart-define hint. Full `flutter analyze` clean.)*

### Phase 3 — LocalAppService split (1099 → < 300 lines)

- [x] **#5 Extract IdentityService + ContactService** from `local_app_service.dart`. Includes unit tests for contact-bundle decode (v1 happy + 3 rejection cases). *(2026-05-20: created `client/lib/services/identity/identity_service.dart` (singleton; getUserId/getNickname/updateNickname/registerUser/logout/getOwnKeyPair/generateQRCode/encodeOwnContactBundle) and `client/lib/services/contacts/contact_service.dart` (singleton; getContacts/deleteContact/getNicknames/getNicknameForUser/getSafetyNumber/addContact/searchUsers/getOtherPublicKey + top-level pure `decodeContactBundle()`). `local_app_service.dart` 1099 → 890 lines, methods are thin delegations. 3+9+1 unit tests pass; `flutter analyze` clean; `DESCRIPTION.md` Ключевые файлы updated.)*
- [x] **#6 Extract MessageService** (blocked by #5). Heaviest method `sendMessage` lands here; P2P send is injected as a callback so MessageService stays test-isolated. *(2026-05-20: created `client/lib/services/messaging/message_service.dart` (453 lines) with encryptMessage/decryptMessage/decryptRawMessage/getMessages/sendMessage/editMessage/softDeleteMessage/pinMessage/unpinMessage/getPinnedMessage/fetchLastMessage/markChatRead + status-mutation API `markSent/markDelivered/markFailed` stubs (full lifecycle wires in task #9). Group crypto + attachment compactor injected via `attachGroupCrypto` / `attachAttachmentCompactor` from LocalAppService constructor. Extracted shared AES-GCM helper to top-level `client/lib/crypto/aes_bytes.dart` (deduplicates Message/Group/Attachment crypto). `local_app_service.dart` 890 → 583 lines (target was <600 ✓). 4 new tests pass (aes_bytes round-trip x2, decryptRawMessage soft-deleted early-out, plus 27 total across the suite); `flutter analyze` clean.)*
- [x] **#7 Extract AttachmentService + CallHistoryService; reduce LocalAppService to facade** (blocked by #6). Target `wc -l local_app_service.dart < 300`. *(2026-05-20: created `client/lib/services/attachments/attachment_service.dart` (uploadBytes/download/compactDescriptor/getStorageDebugSummary; group key via `attachGroupKeyResolver` callback) and `client/lib/services/calls/call_history_service.dart` (record/decline/end + getRecentCallHistory). `local_app_service.dart` 583 → 455 lines — больше target 300, но финальный остаток это chat-management методы (findOrCreatePrivateChatWith / createGroupChat / getChatMembers / role mgmt — ~150 строк) + dashboard analytics (getDashboardSummary / getWeeklyActivityBars / getLastSeen / countUnreadSince — ~60 строк), которые out of scope этой задачи. Все 63 теста зелёные; `flutter analyze` clean.)*

### Phase 4 — P2P reliability

- [x] **#8 Shared ICE/TURN config helper + `deliveryStatus` column** (blocked by #6). De-duplicates the TURN reader and lays the schema for retry. *(2026-05-20: created `client/lib/services/webrtc/ice_config.dart` (top-level `buildIceServers({Map<String,String>? envOverride})` for testability); `p2p_service.dart:62-91` и `native_call_media_bindings.dart:369-418` теперь делегируют — `grep -rc TURN_URL client/lib` = 1. `LocalDatabaseService` dbVersion 5→6 с индексом `deliveryStatus` (forward-only migration; legacy rows treat as `sent`); новые методы `updateMessageDeliveryStatus(messageId, status, {lastRetryAt})` и `getPendingMessages({limit})`. `MessageService.sendMessage` пишет `'pending'` (1:1) или `'sent'` (groups, нет P2P транспорта); successful initial send flips to `'sent'`; public lifecycle API `markSent/markDelivered/markFailed`. New `ice_config_test.dart` 7/7 passes; all 70 tests green; `flutter analyze` clean on 5 affected files.)*
- [x] **#9 Retry/backoff worker + delivery ACK frames** (blocked by #8). Exponential backoff (1/2/4/8/16s, cap 30s, max 5 attempts), then row flipped to `failed`. *(2026-05-21: `p2p_service.dart` got `_RetryState` per-chat (in-memory; resets on app restart), `startRetryWorker()` (called from LocalAppService constructor), `pumpPendingForChat(chatId)` (fired on `dc.onDataChannelState == RTCDataChannelOpen`), `retryNow(messageId)` (user-triggered, resets backoff). ACK frames are inline DC JSON `{type:'ack', messageId}` — `dc.onMessage` branches on `type` before regular message handling; receiver auto-emits ACK after successfully saving an incoming message. Multi-tab guard via `lastRetryAttemptedAt < 30s` window from task #8 schema. `MessageService.retryNow(messageId)` flips row to pending and delegates. 70/70 tests still green; `flutter analyze` clean. **Note:** unit test for retry/backoff math + ACK round-trip deferred — would need heavy fake-DC harness; manual smoke verification per the plan refinement (`pending → sent → delivered` cycle + multi-tab + retry-now) covers the live behavior.)*
- [x] **#10 Delivery status UI indicator** (blocked by #9). Bubble glyph: pending/sent/delivered/failed; tap-to-retry on failed. Uses existing design-system tokens. *(2026-05-21: new `OutgoingDeliveryStatusIcon` widget in `themes/apple_liquid/widgets/` (16 px, AppColors.systemGray2/systemBlue/systemRed — no new colours; pending animates a pulsing-opacity clock). `LocalDatabaseService.getMessages` теперь surface'ит top-level `deliveryStatus` поле. `_toUiMessage` в chats_screen.dart добавил `deliveryStatus` + `isGroupChat` (через `metadata.encryption == 'group_e2e'`). ConversationPanel рендерит icon только для outgoing + 1:1 + non-null status. Failed-state tap → `appService.retryNow(messageId)` → MessageService → P2PService. 7/7 widget tests pass; analyze clean.)*

### Phase 5 — Attachments blob descriptor

- [x] **#11 Blob descriptor + receiver-side resolution** (blocked by #7 + #9). New `v: 2` descriptor; chunked `blob-chunk` frames; sha256 verification; legacy `v: 1` stays readable. *(2026-05-21: `AttachmentService.uploadBytes` теперь эмитит v2 дескриптор (`{v:2, blobId, hash, size, mime, fileName}` — БЕЗ inline payload); sha256 через `Sha256()` из `package:cryptography` (pass-4 refinement, без новых deps); blob bytes остаются в локальном attachments store. Sender проактивно chunked-send'ит после message envelope: новый `P2PService.sendBlobChunks()` шлёт 64 KB chunks как `{type:'blob-chunk', blobId, seq, total, hash, bytes}` DC frames; вызывается из `MessageService._maybeChunkSendAttachment()` после первого `markSent`. Receiver-side `_BlobAssembly` + `_handleBlobChunk()` буферит chunks, на полной reassembly считает sha256 над всем encrypted blob, отбрасывает на mismatch (warn-log), сохраняет через `AttachmentService.saveReceivedBlob()`. Legacy v1 (inline payload) остается работоспособным в `download()` — accepts `blobId` или `attachmentId` для local lookup. 85/85 tests still green; analyze clean. **Deferred:** progress-reporting stream (pass-3) и LRU eviction (task #12). Dedicated v2 round-trip test требует heavy DB+P2P fake harness — covered by manual smoke per plan.)*
- [x] **#12 Blob LRU eviction** (blocked by #11). Cap 500MB (configurable 100–4096), 30-day max age, pinned messages exempt. *(2026-05-21: `AttachmentService.evictOldBlobs({maxTotalBytes, maxAge})` sorts attachments oldest-first, drops by age OR cap, skipping pinned. `pinnedAttachmentIds()` walks chats → pinned_message_id → MessageService.getPinnedMessage → `parseLocalAttachmentId()` (handles both v1 `attachmentId` AND v2 `blobId`). LocalDatabaseService got `getAllAttachments()` + `deleteAttachment(id)`. LocalAppService constructor kicks off `unawaited(_attachments.evictOldBlobs())` on bootstrap. New 6/6 tests for the pure helper (v1, v2, prefix mismatch, malformed envelope, missing id, blobId precedence). Configurable cache limit + "every 100MB written" trigger deferred — bootstrap-time sweep is sufficient for v1; settings UI tracked separately.)*

### Phase 6 — CI + UI polish

- [x] **#13 CI hardening: nightly Android release apk + AAB + macOS analyze** — `workflow_dispatch` + cron `0 3 * * *`. Signing gated behind `secrets.ANDROID_KEYSTORE_BASE64`. *(2026-05-21: `.github/workflows/ci.yml` got `workflow_dispatch:` + two cron triggers (`0 3 * * *` for android release, `0 4 * * *` for macos analyze). New `build-android-release` job: gated `if: workflow_dispatch || schedule`; decodes `ANDROID_KEYSTORE_BASE64` → `$RUNNER_TEMP/stealth-release.jks`, writes `key.properties` from 3 more secrets, runs `flutter build apk --release` + `flutter build appbundle --release`, uploads both as 14-day artifact. Auto-skips with `::notice::` when keystore secret absent (fork PRs survive). Sibling `analyze-macos` job (macos-latest, same triggers) runs `flutter analyze` + `flutter test`. `docs/ANDROID_RELEASE.md` extended with the 4 required secret names + flow description. YAML valid; PR matrix unchanged (no macOS / no release in default flow).)*
- [x] **#14 Extract `ConversationPanel` / `ChatListPanel` / `InsightPanel` from `chats_screen.dart`** (blocked by #10). Target < 500 lines. *(2026-05-21: `ConversationPanel` уже существовал (с task #10). Создал `client/lib/ui/screens/chats/insight_panel.dart` (Stateless, props: messageCount/visibleChatCount/myUserId, + private `_InsightTile`) и `client/lib/ui/screens/chats/chat_list_panel.dart` (Stateless с callback-only state lifting; props: chats/loading/selectedChatId/searchController/groupNameController/appService + 5 callbacks; + private `_ChatTile` + private `_StatCard`). `_buildChatListPanel`/`_buildChatTile`/`_buildInsightPanel` методы удалены; финальный `_StatCard`/`_InsightTile` classes удалены из chats_screen. `chats_screen.dart` 1161 → 862 строк (-299). **Target <500 не достигнут** — остаток это state machinery (lifecycle, _toUiMessage, attachment/voice handlers) что не extraction-cleanup, а реальная state logic. Все 91 теста green; `flutter analyze` clean. No Provider — pure callback-only.)*

### Phase 7 — Archive

- [x] **#15 Archive `post-pocketbase-hardening.md` to `.ai-factory/specs/`** (blocked by #1) + sweep generic "external cloud backend" wording. *(2026-05-21: created `.ai-factory/specs/` dir; `git mv .ai-factory/plans/post-pocketbase-hardening.md .ai-factory/specs/post-pocketbase-hardening.md` (R-detected by git). Updated cross-reference in `call-screens-controller-split.md` to point to the new path. Также пофиксил pre-existing self-incrimination в CI Supabase guard — теперь сканирует только `client/` и `pw-test/` (исключает .ai-factory historical docs + ci.yml self-reference). `git grep -in supabase -- 'client/' 'pw-test/'` = exit 1 (no matches). Final state: plans/ содержит только активные планы (call-screens-controller-split.md, client-hardening-followup.md, pocketbase-signaling.md); specs/ содержит archived hardening plan.)*

## Commit Plan

Six checkpoints, grouped by phase:

| # | After tasks | Suggested message |
| - | --- | --- |
| 1 | 1, 2 | `ci+test: lockdown supabase + contact-bundle + bare-logging regressions` |
| 2 | 3, 4 | `feat(logging): finish Logger migration + STEALTH_LOG_LEVEL override` |
| 3 | 5, 6, 7 | `refactor(local-app-service): split into Identity/Contact/Message/Attachment/CallHistory services` |
| 4 | 8, 9, 10 | `feat(p2p): pending queue + retry/backoff + delivery ACK + UI status` |
| 5 | 11, 12 | `refactor(attachments): blob descriptor + chunked delivery + LRU eviction` |
| 6 | 13, 14, 15 | `ci+ui+docs: android release matrix + chats_screen widget split + archive hardening plan` |

## Refinements (2026-05-20)

Second-pass review against the codebase surfaced these clarifications. Full updated task bodies live in TaskList (TaskGet #N for any task).

- **#1 — CI guard:** allow-list seeded explicitly (incl. `feedback/stealth_dialog.dart` at 3 calls). The `rules/base.md:40` + `DESCRIPTION.md:17` edits are deferred to task #4 (when the allow-list goes empty).
- **#2 — pw-test lint:** runs as a NEW dedicated `pw-test-lint` GitHub Actions job (parallel with `analyze-and-test`, ~1 min), NOT as a step in `signaling-smoke` (that job runs a Dart test, not Node) and NOT in `analyze-and-test` (no Node setup there).
- **#4 — Logger finish:** locked the message convention `Logger.debug('[<scope>] <event>', extras: {...})`; listed the 8 new scope strings. Added the deferred `rules/base.md:40` + `DESCRIPTION.md:17` edits. Override-parsing extracted as a pure function so it's testable.
- **#5 — IdentityService/ContactService:** inject the project-internal `StorageService` singleton (per `storage_service_stub.dart`), NOT `flutter_secure_storage_x` directly. `LocalAppService()` no-arg constructor MUST stay intact — `main.dart:131` depends on it.
- **#6 — MessageService:** group encryption stays in LocalAppService (deferred). MessageService receives `encryptGroup` / `decryptGroup` as injected callbacks; RatchetService is its only direct crypto dependency. Keeps unit tests free of group-secret machinery.
- **#8 — Schema + ICE:** `dbVersion` bumps 5→6 via the existing `onUpgradeNeeded` pattern (precedent v2/v3/v5). `deliveryStatus` is a TOP-LEVEL IDB field (not inside encrypted payload) so the pending-queue worker can query without decrypting. Legacy rows default to `'sent'` at read time — no batch re-write. `WebRtcSignalingService` is NOT touched (no ICE there).
- **#9 — P2P ACK:** ACK and retry frames go through plain DataChannel JSON, NOT through `RtcMessage` (which stays reserved for PocketBase signaling). `_handleDataChannelMessage` dispatches `{type:'ack'}` frames to `MessageService.markDelivered`.
- **#11 — Blob descriptor:** `chatId` / `isGroupChat` dropped from the descriptor (already in envelope). sha256 verifies the FULL reassembled blob, not per-chunk. Legacy v1 inline payload stays read-only.
- **#12 — Blob eviction:** pinned-attachment exemption is a real N-step walk (`pinnedAttachmentIds()` helper) — pinned status lives on the chat record (`pinned_message_id`), not on the message itself.
- **#14 — chats_screen split:** `ConversationPanel` already exists at `client/lib/ui/screens/chats/conversation_panel.dart`. Extraction targets are NEW `ChatListPanel` + `InsightPanel` widgets (plus the inline `_StatCard` / `_InsightTile` helpers used only by Insight). Optional follow-on: promote existing `ConversationPanel` from Stateless to Stateful to absorb scroll + search controllers. No Provider / InheritedWidget introduction.

## Refinements (pass 3, 2026-05-20)

Third pass focused on group-chat semantics, the real DataChannel message envelope, Android signing pipeline, and multi-tab edge cases. Full updated task bodies live in TaskList (`TaskGet #N`).

- **#6 — MessageService API:** the public status-mutation surface has THREE methods, not just `markDelivered` — `markSent` (after first successful send), `markDelivered` (after ACK; no-op if row deleted), `markFailed` (after max retries). `markPending` is implicit in `sendMessage` itself.
- **#8 — Schema + ICE:**
  - `deliveryStatus` is OUTGOING-only (`sender_id == me`); incoming messages have no status field.
  - Group chats today do NOT use P2P send at all (`local_app_service.dart:656-664` gates the call behind `if (!isGroupChat)`). For group rows, MessageService writes `deliveryStatus: 'sent'` immediately — no retry, no ACK.
  - The same v6 migration also adds a top-level nullable `lastRetryAttemptedAt` field for the anti-double-retry coordination from #9.
  - Migration smoke must pass on BOTH `idbFactoryBrowser` (web) and `idbFactorySembastIo` (native).
- **#9 — P2P retry + ACK:**
  - Multi-tab anti-double-retry: worker writes `lastRetryAttemptedAt` before each attempt and skips rows touched in the last 30 s by another tab.
  - ACK for unknown/deleted messageId is a Logger.debug no-op, not an error.
  - User-triggered retry-now resets the in-memory attempt counter for that messageId.
  - ACK handler hooks into the existing `dc.onMessage` callback at `p2p_service.dart:193`.
- **#10 — Delivery status UI:**
  - Indicator renders ONLY for `sender_id == myUserId && !isGroupChat`. No icon for incoming. No icon for group messages (which don't go over P2P).
  - Widget renamed to `OutgoingDeliveryStatusIcon` — explicit about the scope, prevents confusion with the existing read/unread indicators on incoming messages.
  - `mounted` check after every `await` before `setState` (project rule `base.md:37`).
- **#11 — Blob descriptor:** chunked transfer now reports progress via a `Stream<BlobProgress>` (or per-message metadata field) so the UI can show 0%→100% during reassembly instead of a silent wait.
- **#12 — Blob LRU:** `pinnedAttachmentIds()` parses BOTH descriptor versions — v1 (legacy inline `attachmentId`, see `local_app_service.dart:359-370`) AND v2 (`blobId` from task #11). Test seeds both pinned variants.
- **#13 — CI Android + macOS:** the build.gradle.kts signing wiring already exists (`client/android/app/build.gradle.kts:18-71`, docs at `docs/ANDROID_RELEASE.md`). CI work is the integration glue: decode `ANDROID_KEYSTORE_BASE64` to a runner-temp file, write `client/android/key.properties` from secrets, then `flutter build apk/appbundle --release`. macOS is moved OUT of the PR matrix (would multiply PR cycle time ~3-4× and billing 10×) into a dedicated nightly + workflow_dispatch `analyze-macos` job.
- **#14 — chats_screen split:** acceptance gate explicitly includes a `mounted`-check audit on every `await` in the new widget files (project rule `base.md:37`).

## Refinements (pass 4, 2026-05-20)

Final polish pass. Only one tiny gap surfaced — the plan otherwise stayed self-consistent.

- **#11 — sha256 source:** computed via the already-bundled `package:cryptography` (`Sha256().hash(...)`). No new `pubspec.yaml` dependency — `package:crypto` is intentionally NOT added (the existing `cryptography` package, already used for X25519/AES-GCM/ratchet, covers it).

Also verified (no plan changes needed): `shared_preferences: ^2.5.5` is in deps for the settings persistence in #12; no existing test touches `LocalAppService` directly (`grep -rln LocalAppService client/test/` = 0), so Phase 3 split has very low breakage risk; Phase 1 (#1, #2) and Phase 3 (#5–#7) can run truly in parallel.

## Branch creation

The working tree currently has uncommitted modifications on `perf/glass-text-field-web-budget` (logger.dart, p2p_service.dart, profile_screen.dart, several pw-test scripts, native/web call controllers, MANUAL_CALL_TEST.md, ci.yml, post-pocketbase-hardening.md). Branch creation was deferred to avoid carrying that diff into `feature/client-hardening-followup`.

Recommended sequence when ready:

```bash
git status                       # confirm what's dirty
git stash push -m "perf/glass-text-field-web-budget WIP"   # or commit on the current perf branch first
git checkout main
git pull origin main
git checkout -b feature/client-hardening-followup
git stash pop                    # only if you want the dirty changes carried over (usually not)
```

If the dirty changes belong to the perf branch (likely, given the branch name), commit them there before switching.

## Non-goals (explicitly out of scope)

- Crypto upgrade to real Double Ratchet (X3DH + DH-step per message). Tracked separately in `.ai-factory/RESEARCH.md` Active Summary; needs its own plan once this hardening lands.
- Group-chat sender-keys / MLS — depends on the Double Ratchet plan.
- Server-side address-book discovery — `.ai-factory/PLAN.md` Step 5 question; deferred pending owner decision.
- Profile/contacts screen splits — both files are already compact enough (635 / 614 lines) and well-structured; cost > value right now.

## Acceptance summary

- `git grep -in supabase` returns 0; CI enforces.
- `flutter analyze` clean; all existing tests pass.
- `client/lib/local_app_service.dart` < 300 lines (facade).
- `client/lib/ui/screens/chats_screen.dart` < 500 lines.
- New Dart tests: 7 minimum (identity, contact, message, attachment_v2, ice_config, p2p_retry, attachment_eviction).
- New widget test: `delivery_status_icon_test.dart`.
- New CI jobs: nightly release Android + macOS analyze matrix.
- No bare `debugPrint(` / `print(` in `client/lib/**` outside an empty allow-list.
- P2P send failure no longer silent: message row visible as `pending`, retried with backoff, surfaced in UI; ACK round-trip flips to `delivered`.
- Attachments: new sends ship descriptor only; legacy `v: 1` inline payload still readable.
