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

1. **CI guard: zero Supabase + ban bare logging in `client/lib`** — adds a `git grep` step + a new Dart regression test with an allow-list seeded from the currently-offending files.
2. **pw-test guard: forbid raw UUID in add-contact flows** — new `pw-test/lint-contact-bundle.mjs` + CI step.

### Phase 2 — Finish Logger migration

3. **Migrate `native_call_media_bindings.dart` + `web_call_media_bindings.dart` to Logger** (blocked by #1). 27 calls combined; sensitive ids pass through `_sensitiveKeys` redaction.
4. **Migrate remaining `debugPrint` + add `STEALTH_LOG_LEVEL` dart-define override** (blocked by #3). Lifts the allow-list to empty.

### Phase 3 — LocalAppService split (1099 → < 300 lines)

5. **Extract IdentityService + ContactService** from `local_app_service.dart`. Includes unit tests for contact-bundle decode (v1 happy + 3 rejection cases).
6. **Extract MessageService** (blocked by #5). Heaviest method `sendMessage` lands here; P2P send is injected as a callback so MessageService stays test-isolated.
7. **Extract AttachmentService + CallHistoryService; reduce LocalAppService to facade** (blocked by #6). Target `wc -l local_app_service.dart < 300`.

### Phase 4 — P2P reliability

8. **Shared ICE/TURN config helper + `deliveryStatus` column** (blocked by #6). De-duplicates the TURN reader and lays the schema for retry.
9. **Retry/backoff worker + delivery ACK frames** (blocked by #8). Exponential backoff (1/2/4/8/16s, cap 30s, max 5 attempts), then row flipped to `failed`.
10. **Delivery status UI indicator** (blocked by #9). Bubble glyph: pending/sent/delivered/failed; tap-to-retry on failed. Uses existing design-system tokens.

### Phase 5 — Attachments blob descriptor

11. **Blob descriptor + receiver-side resolution** (blocked by #7 + #9). New `v: 2` descriptor; chunked `blob-chunk` frames; sha256 verification; legacy `v: 1` stays readable.
12. **Blob LRU eviction** (blocked by #11). Cap 500MB (configurable 100–4096), 30-day max age, pinned messages exempt.

### Phase 6 — CI + UI polish

13. **CI hardening: nightly Android release apk + AAB + macOS analyze** — `workflow_dispatch` + cron `0 3 * * *`. Signing gated behind `secrets.ANDROID_KEYSTORE_BASE64`.
14. **Extract `ConversationPanel` / `ChatListPanel` / `InsightPanel` from `chats_screen.dart`** (blocked by #10). Target < 500 lines.

### Phase 7 — Archive

15. **Archive `post-pocketbase-hardening.md` to `.ai-factory/specs/`** (blocked by #1) + sweep generic "external cloud backend" wording.

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
