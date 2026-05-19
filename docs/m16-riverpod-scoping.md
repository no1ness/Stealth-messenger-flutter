# M16 — Riverpod DI + secure-storage refactor scoping

**Roadmap milestone:** [M16 — Riverpod DI + secure-storage refactor](../.ai-factory/ROADMAP.md) (`Future direction, awaiting prerequisite`)
**Status:** scoping document; no code changes
**Created:** 2026-05-19
**Author:** /aif-implement (M16 scope)
**Prerequisite for implementation:** M10 (Design system v2) must merge first so the audit covers the final state surfaces, not the pre-refactor ones
**Companion docs:** `client/lib/themes/theme_controller.dart` (the explicit "stepping stone to Riverpod" comment), `feature/hardening-di-secure-storage` branch (referenced in design-refactor plan)

This document audits the current state-surface inventory in the Stealth client, draws provider boundaries for a future Riverpod migration, and proposes a migration ordering. **No code is changed in this PR**, and **no migration is recommended to start before M10 (PR #3) merges** — the design refactor adds at least one new `ValueNotifier`, so an audit done today would be incomplete.

---

## TL;DR

1. **Current state surfaces fall into three buckets:**
   - **Strict singletons** (static instance, must be reset for tests): `StorageService` × 3 platform files, `P2PService`, `PocketBaseClient`. Already painful — `PocketBaseClient` has a `resetForTests()` static method, which is the canonical "testability pressure point" smell.
   - **Instantiated-everywhere** (no singleton, but de-facto shared via underlying state): `LocalDatabaseService` and `LocalAppService` are constructed fresh in 5+ sites each. They share state via the encrypted DB file, so functionally they're singletons; the code just doesn't admit it.
   - **Listenables** (post-M10 only): `ThemeController.mode` is a top-level `ValueNotifier<ThemeMode>` — explicitly documented (`theme_controller.dart:7–15`) as a Riverpod-ready stepping stone with API surface designed to flip to a `themeModeProvider` without screen-tree changes.
2. **Recommended target architecture:** 5 provider tiers (env, storage, identity, signaling, services + UI listenables). Each tier has clear dependencies on tiers below it. No circular deps; all overridable in tests via `ProviderScope.overrides`.
3. **Recommended ordering:** Storage tier first (it's the deepest dependency), then identity (which depends on storage), then signaling (depends on identity + env), then services (depends on signaling + storage + identity), then UI listenables. Each tier is its own PR. Existing call sites are migrated incrementally — old singleton API can stay alive in parallel during the migration via thin delegating wrappers.
4. **Estimated scope:** 5–7 PRs over 1500–2500 LOC of code changes + ~200 LOC of provider tests. Substantially larger than M14 (1 PR) or M15 (1 ratchet refactor PR + tests). Compensating benefit: every future feature stops needing custom test setup boilerplate.
5. **Open questions for owner:** whether to keep `LocalDatabaseService`/`LocalAppService` as instantiated-everywhere (just inject the storage they need) or migrate them to providers too; whether to bring `riverpod_generator` (code-generated providers, less boilerplate, adds a build_runner step).

---

## Part 1 — Current state-surface audit

### Tier S — Strict singletons (`static instance` + `resetForTests()` is the smell)

| Site | Pattern | Friction signal |
|---|---|---|
| `client/lib/storage_service_io.dart:4` (Android/iOS) | `static final StorageService _instance = StorageService._internal();` | Three platform-conditional copies via conditional imports |
| `client/lib/storage_service_stub.dart:4` (test fallback) | same | Same |
| `client/lib/storage_service_web.dart:24` (web) | same | Same |
| `client/lib/p2p_service.dart:13` | `static final P2PService instance = P2PService._();` | Tests must reach inside and tear down per-test |
| `client/lib/services/signaling/pocketbase_client.dart:20–43` | Lazy singleton `static PocketBaseClient? _instance;` + `static void resetForTests()` | **`resetForTests()` is the canonical "testability pressure point" smell** — code admits it doesn't want to be a singleton but is anyway |

### Tier I — Instantiated-everywhere (de-facto singletons via shared underlying state)

| Site | Pattern | What's actually shared |
|---|---|---|
| `client/lib/local_database_service.dart:12` instantiated in 4+ sites | `final LocalDatabaseService _localDb = LocalDatabaseService();` in `p2p_service.dart:15`, `local_app_service.dart:19`, `peer_resolver.dart:28`, ... | The encrypted SQLite/indexeddb file. New instances of the class share the file. |
| `client/lib/local_app_service.dart:15–19` instantiated 5+ times | `final LocalAppService _appService = LocalAppService();` in `registration_screen.dart:20`, `main.dart:136`, `p2p_discovery_service.dart:6`, `apple_liquid_app.dart:21`, ... | Wraps `LocalDatabaseService` + identity bundle; same underlying file. |

These look stateless at the class level but aren't — the *file* is the singleton. Calling `LocalDatabaseService()` 5 times doesn't create 5 separate state spaces; it creates 5 handles to the same one. This is fine in production but is exactly the kind of "implicit global state" Riverpod is designed to make explicit.

### Tier L — Listenables (post-M10 only)

| Site | Pattern | Already-Riverpod-shaped? |
|---|---|---|
| `client/lib/themes/theme_controller.dart:23` (lands with M10/PR #3) | `static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.dark);` | **Yes by design.** The class doc explicitly says: *"on merge with `feature/hardening-di-secure-storage`, swap this `ValueNotifier` for a `themeModeProvider` without touching any screen-level code (the API surface stays the same)."* |

If M10 introduces any other listenables during its refinement (e.g., a top-level `ValueNotifier<bool>` for design-system feature flags), this audit needs to be re-run post-M10-merge. That's the M16 prerequisite.

---

## Part 2 — Proposed target architecture

Five provider tiers, organized by dependency direction (each tier may depend on tiers *below* it; never above):

```
┌─────────────────────────────────────────────────────────────┐
│ Tier 5 — UI listenables                                      │
│   themeModeProvider (StateNotifierProvider<ThemeMode>)       │
│   (post-M10: any other UI-state notifiers from design-sys)   │
└─────────────────────────────────────────────────────────────┘
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Tier 4 — App services                                        │
│   localAppServiceProvider (Provider<LocalAppService>)        │
│   p2pServiceProvider (Provider<P2PService>)                  │
│   p2pDiscoveryServiceProvider (Provider<P2PDiscoveryService>) │
└─────────────────────────────────────────────────────────────┘
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Tier 3 — Signaling                                           │
│   pocketBaseClientProvider (Provider<PocketBaseClient>)      │
│   incomingCallServiceProvider (Provider<IncomingCallService>) │
│   webRtcSignalingServiceProvider (Provider.family<...>)      │
└─────────────────────────────────────────────────────────────┘
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Tier 2 — Identity                                            │
│   selfUserIdProvider (FutureProvider<String>)                │
│   localDatabaseServiceProvider (Provider<LocalDatabaseService>) │
└─────────────────────────────────────────────────────────────┘
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Tier 1 — Foundation                                          │
│   envProvider (Provider<Map<String,String>>)                 │
│   storageServiceProvider (Provider<StorageService>)          │
│   loggerProvider (Provider<Logger>)                          │
└─────────────────────────────────────────────────────────────┘
```

### Design constraints

1. **No circular dependencies.** Tier N may only `ref.watch(tierMProvider)` where M < N. If a circle would form, that's a sign the design needs splitting (e.g., extracting a config object).
2. **All providers are overridable in tests.** `ProviderScope(overrides: [storageServiceProvider.overrideWithValue(FakeStorage())])` replaces the foundation tier; every dependent provider transparently uses the fake. No more `resetForTests()` static methods.
3. **Keep public APIs of existing services unchanged.** `P2PService.connectToPeer(chatId)` remains a method call. Riverpod is the wiring; the API shape doesn't change. This preserves the M3 PocketBase identity contract and every other existing contract.
4. **No `Consumer`/`ConsumerWidget` rebuild on every state change.** Use `Consumer(builder: ...)` for fine-grained widgets; coarse-grained screens use `ref.watch` only for the providers they actually need. Standard Riverpod hygiene.

---

## Part 3 — Migration ordering

5 PRs total, each tier in its own PR. Each lands as a strict superset of the previous (no breaking changes mid-migration).

### PR 1 — Foundation tier

- Add `flutter_riverpod` to `pubspec.yaml`.
- Wrap `main.dart`'s `runApp` in `ProviderScope`.
- Introduce `envProvider`, `storageServiceProvider`, `loggerProvider`.
- **Keep `StorageService.instance` working** via a thin delegate: `static StorageService get instance => _container?.read(storageServiceProvider) ?? <fallback>`. This lets existing call sites keep working unchanged during the migration.
- Tests: provider override tests for each foundation provider.

**Estimated scope:** 200–300 LOC. Mostly setup + delegates.

### PR 2 — Identity tier

- `localDatabaseServiceProvider` constructs `LocalDatabaseService` once per `ProviderScope`. Tier-1 storage is injected.
- `selfUserIdProvider` reads from `StorageService`, exposes self UUID as a Future.
- Migrate call sites that use `LocalDatabaseService()` directly: replace with `ref.watch(localDatabaseServiceProvider)`. **Both call patterns work at once** during the migration — the old constructor still functions but is marked `@Deprecated('Use localDatabaseServiceProvider')`.

**Estimated scope:** 400–600 LOC across ~10–15 call sites. The bulk of the migration.

### PR 3 — Signaling tier

- `pocketBaseClientProvider` replaces the lazy singleton + `resetForTests()`.
- `incomingCallServiceProvider`, `webRtcSignalingServiceProvider` follow.
- **Remove `resetForTests()` from `pocketbase_client.dart`** — provider scope rebuild handles per-test reset automatically.

**Estimated scope:** 300–450 LOC. Smaller than tier 2 because fewer call sites.

### PR 4 — App services tier

- `localAppServiceProvider`, `p2pServiceProvider`, `p2pDiscoveryServiceProvider`.
- Migrate the 5 screens that construct `LocalAppService()` to `ref.watch(localAppServiceProvider)`.

**Estimated scope:** 250–400 LOC.

### PR 5 — UI listenables (`themeModeProvider`)

- Migrate `ThemeController.mode` (`ValueNotifier<ThemeMode>`) to a `StateNotifierProvider<ThemeModeNotifier, ThemeMode>`.
- The class doc on `theme_controller.dart` (lines 7–15) literally says this is the planned migration. Honor it.
- Update `ValueListenableBuilder` consumers (introduced in M10) to `Consumer(builder: (ctx, ref, _) => ...)`.

**Estimated scope:** 150–250 LOC. Smallest because the design was already Riverpod-shaped.

### Decommissioning

After all 5 tier PRs merge:

- Remove the delegating wrappers introduced in PR 1 (`StorageService.instance` static, etc).
- Remove the `@Deprecated` annotations from PR 2.
- A final PR consolidates and removes legacy patterns.

**Estimated cleanup scope:** 100–200 LOC of deletions.

---

## Part 4 — Test impact

This is the largest non-feature benefit. Every test currently doing one of:

- `StorageService.instance` → mocked via MethodChannel (`flutter_secure_storage_x_mock_test.dart` pattern)
- `PocketBaseClient.resetForTests()` → manual lifecycle in setUp/tearDown
- `LocalDatabaseService()` direct construction → tests share the same DB file unless they wipe between runs
- `ThemeController.mode.value = ...` → manual state poke

…can become:

```dart
testWidgets('foo', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(FakeStorage()),
        themeModeProvider.overrideWith((ref) => ThemeMode.light),
      ],
      child: const MyApp(),
    ),
  );
  // ...
});
```

No more static reset functions, no more shared-file-state surprises.

### Existing security regression tests still apply

- `secure_storage_policy_test.dart` — still passes; the wrapper that enforces the policy still exists, just exposed through a provider.
- `private_key_no_export_test.dart` — orthogonal to DI; still passes.

The migration doesn't weaken any existing security gate.

---

## Part 5 — Open questions for the project owner

1. **Should `LocalDatabaseService` and `LocalAppService` migrate to providers?** They're not strict singletons today (just instantiated-everywhere), so leaving them as-is is *not* broken — but the migration would make their shared-state contract explicit. Recommendation: yes, migrate them (Part 3 PR 2, PR 4) — the friction of having two patterns long-term is worse than the one-time migration cost.
2. **`riverpod_generator` or hand-written providers?** Code-generated providers (`@riverpod` annotation + `build_runner`) reduce boilerplate but introduce a build step. The project doesn't currently use `build_runner` (no `*.g.dart` files in `lib/` based on a quick check). Recommendation: hand-written — adding `build_runner` to the toolchain for one feature is too much new surface.
3. **What's the relationship with the `feature/hardening-di-secure-storage` branch?** Referenced in `theme_controller.dart`'s doc comment as the Riverpod-introducing branch. If that branch already has Riverpod scaffolding, M16 may rebase on it rather than re-derive. **Need to inspect that branch before opening any of the 5 implementation PRs.**
4. **Acceptable PR sequence pace?** 5 PRs is a lot. Some teams prefer one giant migration PR; some prefer the tier-at-a-time split here. Tier-at-a-time is recommended (safer, easier to review, can pause mid-migration if priorities change), but it's owner-territory.
5. **Migration deadline / forcing function?** Riverpod doesn't have to happen on a schedule. The forcing function would be: "the next major feature that needs to mock state will benefit so much from Riverpod that doing it before that feature is worth the up-front cost." If no such feature is in the next 3 months, M16 can sit at `[ ]` indefinitely.

---

## Part 6 — Next concrete step

**Do not start implementation yet.** M16 has two hard prerequisites:

1. **M10 (PR #3) must merge** so the audit covers the final post-design-refactor state. This doc explicitly notes that M10 may add UI listenables beyond `themeModeProvider`; those need to be in scope.
2. **`feature/hardening-di-secure-storage` branch must be inspected** to determine whether M16 PR 1 builds on it or replaces it.

After both prerequisites resolve:

```
/aif-plan full
  Migrate Stealth client to Riverpod DI per docs/m16-riverpod-scoping.md.
  Tier-at-a-time, 5 PRs. Foundation → identity → signaling → services →
  UI listenables. Delegating wrappers preserve old singleton API during
  migration.
```

The plan will reference this scoping doc as its primary requirements source.

---

## Appendix — Diagnostic queries used to build this audit

These commands reproduce the state-surface inventory from `main`. Useful for the future implementation PR's verification step.

```bash
# Strict singletons
grep -rnE "static.*instance|factory.*\._?\(\)" client/lib --include="*.dart" \
  | grep -v "test\|_test"

# Instantiation sites for "instantiated-everywhere" services
grep -rnE "LocalDatabaseService\(\)|LocalAppService\(\)" client/lib --include="*.dart"

# Existing ValueNotifier sites (currently empty on main; populated post-M10)
grep -rn "ValueNotifier" client/lib --include="*.dart"

# Testability-friction smell: resetForTests() static methods
grep -rn "resetForTests" client/lib --include="*.dart"
```

Run these before opening the M16 implementation PR to verify nothing material has drifted since this scoping doc was written.
