# Roadmap

**Created:** 2026-05-19
**Maintained by:** `/aif-roadmap`
**Scope:** sealed, in-flight, and committed-but-not-started milestones. Future-work without a clear commitment lives in `RESEARCH.md`, not here.

This roadmap is the source of truth for milestone-level direction. `/aif-plan` links to milestones from here via `## Roadmap Linkage`; `/aif-verify --strict` reads it for milestone gates; `/aif-implement` marks milestones `[x]` when their backing plan completes.

---

## Status legend

- `[x]` — sealed: shipped to `main`, no follow-up tracked in active plans
- `[~]` — in flight: a PR is open or a branch is actively being worked on
- `[ ]` — committed not started: agreed direction, no code yet
- (no milestone) — speculative; lives in `RESEARCH.md` until promoted

---

## Sealed milestones (chronological)

- [x] **M1 — Local-first architecture rollout.** Cloud backend removed from the runtime; contacts/messages/attachments/call-history live only on-device. Contact discovery via `stealth:<base64url(json)>` bundle exchange. No external backend for these data classes (project rule, enforced).
- [x] **M2 — PocketBase signaling-only contract.** Calls and DataChannel signaling go through PocketBase via SSE. PB stores only transient signaling events. (`feature/pocketbase-signaling`.)
- [x] **M3 — PocketBase identity hardening.** `users.id == pbIdFromLocalUuid(selfUserId)` (15-char SHA-256), symmetric `creatorUuid` in payloads, incoming-call auth race fixed. Hotfix series: `ae47280`, `58d2049`. (`post-pocketbase-hardening` Phase 1.)
- [x] **M4 — Bootstrap & env config.** Committed `.env.defaults` asset, runtime override via `--dart-define`. `.env` removed from asset bundle. Startup error UX points to setup docs. (`post-pocketbase-hardening` Phase 3.)
- [x] **M5 — Structured logging + redaction.** `Logger.debug/info/warn/error` with auto-redaction of sensitive ids above DEBUG. Bare `print()` forbidden in `lib/` (regression-gated). (`post-pocketbase-hardening` Phase 4.)
- [x] **M6 — Honest crypto claims.** `ratchet_service.dart` doc-comment now explicitly states "NOT the Signal Double Ratchet" and "does NOT provide Perfect Forward Secrecy". `docs/SECURITY.md` aligned. (`post-pocketbase-hardening` Phase 6.)
- [x] **M7 — Quality gates infra.** GitHub Actions CI: analyze + test + build web + signaling smoke. `secure_storage_policy_test`, `private_key_no_export_test` regression gates. (`post-pocketbase-hardening` Phases 2, 7.)
- [x] **M8 — chats_screen.dart split + group sheets.** 1794-line `chats_screen.dart` decomposed into `client/lib/ui/screens/chats/` modules (panel + attachment + group-management-sheet). (`post-pocketbase-hardening` Phase 5.)
- [x] **M9 — Android release hardening.** `applicationId` renamed off `com.example.turbo`, release signing config, lint re-enabled. (`post-pocketbase-hardening` Phase 8.)
- [x] **M10.1 — GlassTextField focus-pulse perf budget for web.** `ChromaticAberration.ghostBuilder` API + `kIsWeb` cheap-ghost path (`_GlassFieldGhost`). Transplanted from `perf/glass-text-field-web-budget` into `main` (commit `761f8c2`). **2026-06-14.**

## In flight

- [~] **M10 — Design system v2 (Apple Liquid).** Tokens, primitives, signature effects (ScanlineOverlay, GrainOverlay, ChromaticAberration, DecryptText, key-fingerprint backdrop), `GlassPageRoute`, `StealthHaptics`. Source of truth: `docs/design-system.md` + `docs/design-mockups/`. Backing plan: `.ai-factory/plans/feature-ui-design-refactor.md` (6 refinement passes shipped). **PR #3** open.
- [~] **M9.1 — Re-enable Android CI build-apk.** Scoped under M9 (Android release hardening). `ci.yml` `if: false` gate removed (originally gated in commit `06dbd4c` for slowness; gradle cache now warm). **PR #5** open.

## Committed, not started

- [ ] **M11 — Web rollout readiness + perf benchmarks.** Font subsetting via `pyftsubset` (Geist + Geist Mono → used-glyph subset; expected 60–70% bundle reduction), web-specific perf gates beyond GlassTextField (BackdropFilter-heavy surfaces audit), manual smoke matrix (Chrome / Safari / Firefox). **Performance benchmark harness** (FPS, load time, bundle size, render speed), **monitoring dashboard** (device info, install tracking, platform stats, P2P/WebRTC connection stats, message/call/file counts). Backing plan: `.ai-factory/plans/perf-benchmarks-monitoring.md`. Trigger: stakeholder decision that web is a release target.
- [ ] **M12 — Two-device manual QA program.** Bundle exchange, chat with E2E ratchet, P2P DataChannel, audio/video call on two physical devices (Android×Android, Android×iOS). Trigger: pre-release QA cycle.
- [ ] **M13 — Appium suite sync.** AccessibilityIds contract preserved through M10. Sync the values into the out-of-repo Appium suite; add coverage for `_GlassFieldGhost` if it becomes user-facing. Trigger: post-M10 merge.
- [ ] **M14 — TURN/relay reliability.** Currently `lib/p2p_service.dart:33` notes `TODO: Add TURN servers for better reliability`. Survey traversal-failure rate from production logs, then commit to a TURN provider or self-host. Trigger: traversal-failure metric > threshold.

## Future direction (committed but blocked / awaiting prerequisite)

- [ ] **M15 — Cryptographic upgrade: DH Double Ratchet (PFS).** Current ratchet is a symmetric KDF chain (see M6); a root-key leak compromises all messages. Upgrade to a true Signal-style Double Ratchet to gain PFS. Scope includes ratchet migration plan, backward-compat envelope, and threat-model update in `docs/SECURITY.md`. Prerequisite: M3 (sealed); explicitly future-work, `post-pocketbase-hardening` Phase 6.3.
- [ ] **M16 — Riverpod DI + secure-storage refactor.** Referenced in design-system v2 compatibility note (`feature/hardening-di-secure-storage` branch). Migrate `ThemeController` `ValueNotifier` + signaling-service singletons to Riverpod providers without changing public APIs. **Scope addendum (2026-05-22):** also includes the `chats_screen.dart` <500-line refactor (currently 806 строк после Phase B из FIX_PLAN.md). State machinery (29 полей, 3 domain) требует DI для разделения — без Riverpod дальнейший extraction только перегоняет prop-drilling. Prerequisite: M10 merge.

## Speculative / not on roadmap

Items below live in `.ai-factory/RESEARCH.md` until a backing plan commits to them. Listed here only so contributors don't propose them as "missing" from the roadmap.

- Group chat E2E (currently 1:1)
- Multi-device key sync
- Self-destructing messages / disappearing media
- iOS-specific release hardening (parallel to M9)
- Self-hosted PocketBase deployment automation

---

## How to update

- Promote a speculative item to `[ ]`: open `/aif-plan` for it and add a milestone entry here referencing the plan filename.
- Move `[ ] → [~]`: open the PR and link it.
- Move `[~] → [x]`: when the backing plan completes and merges to `main`, `/aif-implement` checks `Roadmap Linkage` and flips the box.
- Mark a sealed milestone as reopened: do **not** flip `[x] → [ ]` directly. Open a new milestone with a higher number (e.g. M3.1) so history stays linear.
