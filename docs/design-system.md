# Stealth Design System

> Source of truth for the visual language, design tokens, and reusable
> UI primitives in the Stealth Messenger client.
>
> Owners: anyone touching `client/lib/themes/apple_liquid/` or
> `client/lib/ui/screens/`. Changes here must be reflected in widget
> code; widget code must reference these tokens, not magic numbers.
>
> **Visual companion:** [`docs/design-mockups/`](design-mockups/) —
> self-contained HTML pages showing every signature surface in
> context. Open `docs/design-mockups/index.html` in a browser; no
> build step.

---

## Aesthetic direction (north star)

**Refined crypto-noir.**

A signal-grade encrypted messenger that LOOKS like one. Deep blacks
and deep blue-blacks form the dominant canvas. A single sharp accent
(systemBlue) carries every call-to-action and every "this is the live
edge of an encrypted thing" moment. Monospace numerics make every
identifier (user-ids, safety numbers, durations, timestamps) feel
like a value out of `openssl`, not a value out of a settings panel.
A subtle horizontal scan-line lives on outgoing message bubbles and
on high-importance dialogs — the one visual element a user will
remember and identify with Stealth.

We do NOT chase "modern SaaS" softness, purple gradients, or rounded
playfulness. We do NOT use system fonts. We do NOT scatter
micro-interactions; we choreograph a small number of high-impact
moments (a staggered list reveal, a single pulse on send-confirmed,
the E2E ENCRYPTED badge during a call).

| Dimension      | Commitment                                                |
|----------------|-----------------------------------------------------------|
| Palette        | Stealth dark (`#0A0E1A`) dominant + `#151922` cards + a single sharp `#007AFF` accent + selective desaturated cyan |
| Typography     | **Geist Mono** for numerics / IDs / timestamps / hashes; **Geist Sans** for body and UI labels |
| Motion         | `AppMotion.normal` (250 ms) is the default; choreographed page-load reveals over scattered hover toys |
| Signature      | `ScanlineOverlay` on outgoing chat bubbles and on `DialogImportance.high` dialogs; HUD-style call screen |
| Negative space | Generous around the hero `IdentityCard`; controlled density inside chat list and contacts grid |
| Dark / Light   | **Dark is the primary identity.** Light mode is "accessibility / high contrast" — same colors, deliberately fewer ornaments (effects auto-disable) |

### References

Inspirational anchors for the team — not assets to copy, just compass
points:

- Vercel dashboard (Geist family in the wild, monochrome surface, accent restraint).
- Linear "Insights" screen (dense data on dark, monospace numerics, motion discipline).
- 1Password 8 macOS (calm dark surfaces, single accent, refined typography).
- Things 3 (negative space + asymmetric card emphasis).
- Signal call screen (the bar to beat on cryptographic UX clarity).

### Anti-patterns

These are project-wide bugs, not stylistic disagreements:

- `Theme.of(context).colorScheme.*` reads — use `AppColors.*` constants instead. Material 3 ColorScheme is set up but we don't read through it; the project authored its own tokens for a reason.
- Bare `AlertDialog(...)` and bare `ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(...))` — must go through `showStealthDialog` and `showStealthSnackBar`.
- System font fallback (Arial, Roboto, Liberation, SF Pro via stub) — typography MUST resolve to a real Geist face (or another committed family if direction is re-litigated and the docs are updated alongside).
- Inline `EdgeInsets` with magic numbers — must reference `AppSpacing.*`.
- Hardcoded `Duration(milliseconds: ...)` in widget animations — must reference `AppMotion.*`.
- Missing `RepaintBoundary` around an overlay or animated subtree — see "Performance discipline".
- Effects (`ScanlineOverlay`, `GrainOverlay`, `ChromaticAberration`) bleeding into light mode — they auto-gate on `Theme.brightness`; do not bypass with `force: true` outside tests.

---

## Fonts

### Families

| Family       | Role                                                  | Weights bundled  | Files                                                                                                  |
|--------------|-------------------------------------------------------|------------------|--------------------------------------------------------------------------------------------------------|
| `Geist`      | Body, UI labels, headings — every non-numeric string  | 400, 500, 600, 700 | `client/assets/fonts/geist/Geist-{Regular,Medium,SemiBold,Bold}.otf`                                  |
| `GeistMono`  | Numerics, IDs, hashes, timestamps, call duration timer | 400, 500, 600   | `client/assets/fonts/geist-mono/GeistMono-{Regular,Medium,SemiBold}.otf`                                |

Both families are referenced from `client/lib/themes/apple_liquid/constants/app_typography.dart`. Every `TextStyle` declares a `fontFamilyFallback` ladder (`AppFontStacks.sansFallbacks` / `monoFallbacks`) so a missing face does not crash rendering — it degrades to the closest system font.

### Licensing

Both Geist and Geist Mono are released by Vercel under the **SIL Open Font License 1.1** ([source: github.com/vercel/geist-font](https://github.com/vercel/geist-font)). OFL 1.1 permits:

- bundling the font files inside any app or document, including commercial products;
- redistribution of the unmodified font files together with the app binary.

OFL 1.1 requires that the OFL.txt notice ships with the font files when redistributed. We satisfy this by keeping the upstream notice in the repo (see follow-up below).

**No commercial licensing burden. No per-seat fee. Open-source-safe.**

### Asset budget

Current bundle impact (raw OTF, pre-subset):

| File                         | Size    |
|------------------------------|---------|
| Geist-Regular.otf            | ~158 KB |
| Geist-Medium.otf             | ~162 KB |
| Geist-SemiBold.otf           | ~165 KB |
| Geist-Bold.otf               | ~167 KB |
| GeistMono-Regular.otf        | ~173 KB |
| GeistMono-Medium.otf         | ~175 KB |
| GeistMono-SemiBold.otf       | ~178 KB |
| **Total**                    | **~1.18 MB** |

| Budget        | Limit       | Status                                  |
|---------------|-------------|-----------------------------------------|
| Mobile bundle | ≤ +1.5 MB   | ✅ within budget                         |
| Web bundle    | ≤ +600 KB   | ⚠️ over — subsetting required pre-web release |

### Pre-web-release subsetting (follow-up, not blocking Phase 0)

Before the first web release that ships these fonts, run `pyftsubset` (from `fonttools`) to drop unused glyphs. Target Latin Extended + common punctuation; that typically halves each file. Add the subset command to `Makefile` / CI so re-cuts are reproducible:

```
pyftsubset Geist-Regular.otf \
  --unicodes="U+0020-007E,U+00A0-00FF,U+2010-2027,U+2030-205E,U+20A0-20BF" \
  --layout-features='*' \
  --output-file=Geist-Regular.subset.otf
```

After subsetting expect each OTF to drop from ~165 KB to ~75 KB → total ≈ 530 KB, within the web budget.

### Add upstream LICENSE files (housekeeping, not blocking)

OFL 1.1 §1 requires the license notice to travel with the fonts. Drop a copy of `OFL.txt` from the upstream repo at:

- `client/assets/fonts/geist/OFL.txt`
- `client/assets/fonts/geist-mono/OFL.txt`

Tracked as a follow-up; the fonts work without it but distribution compliance requires it.

## Tokens

All tokens live under `client/lib/themes/apple_liquid/constants/`. Reach for the named token first; only inline a literal if the token would obscure the intent of a one-off layout choice (and document why).

### Colors — `app_colors.dart`

| Alias            | Backed by         | When to use                                      |
|------------------|-------------------|--------------------------------------------------|
| `textPrimary`    | `0xFFFFFFFF`       | Default body and heading color on dark surfaces. |
| `textSecondary`  | `0x99FFFFFF`       | Captions, helper text, "less important" UI.      |
| `textTertiary`   | `0x4DFFFFFF`       | Placeholders, disabled labels.                   |
| `textOnGlass`    | alias of `textPrimary` | Text drawn over a `GlassContainer`.          |
| `dividerSubtle`  | alias of `separator`   | `ListDivider` rows, hairline group separation. |
| `surfaceMuted`   | alias of `backgroundTertiary` | Skeleton placeholders, empty-state backgrounds. |
| `statusSuccess`  | alias of `systemGreen` | "It worked" indicators.                       |
| `statusWarn`     | alias of `systemOrange`| "Heads up, recoverable" indicators.           |
| `statusDanger`   | alias of `systemRed`   | Destructive actions, errors, hangup buttons.  |
| `statusInfo`     | alias of `systemBlue`  | Informational chips, the primary accent.      |

### Spacing — `app_spacing.dart`

| Alias              | Value                         | When to use                                                |
|--------------------|-------------------------------|------------------------------------------------------------|
| `screenEdge`       | 16                            | Horizontal inset for any top-level screen.                 |
| `cardPadding`      | 16                            | Inside any `GlassContainer` / card.                        |
| `tileGap`          | 8                             | Gap between rows in lists where rows carry their own padding. |
| `bottomBarOverlap` | `tabBarHeight + 24` (≈80)      | Extra bottom padding on screens with `GlassBottomNavBar`.  |
| `buttonHeight`     | 44 (alias of `buttonHeightMedium`) | iOS-standard touch target.                            |

(Raw scale tokens — `xs / sm / md / lg / xl / xxl / xxxl / huge / massive` — remain available for fine-tuning; prefer semantic aliases when one applies.)

### Motion — `app_motion.dart`

| Token       | Value                | When to use                                              |
|-------------|----------------------|----------------------------------------------------------|
| `fast`      | 150 ms               | Button press, send-confirmed pulse, snackbar enter.      |
| `normal`    | 250 ms               | Dialog scrim fade, list stagger step, theme toggle.      |
| `slow`      | 400 ms               | Modal slide-up, background crossfade, shimmer cycles.    |
| `pageRoute` | 320 ms               | Page-route enter/exit.                                   |
| `emphasized`| `Cubic(0.2, 0, 0, 1)`| Signature easing — choreographed reveals.                |
| `standard`  | `Curves.easeInOut`   | Everyday transitions.                                    |
| `decelerated`| `Curves.fastOutSlowIn`| Dismissals — "fade away" rather than snap.             |

### Elevation — `app_elevation.dart`

| Level   | Composition                                | When to use                                                  |
|---------|--------------------------------------------|--------------------------------------------------------------|
| `level0`| flat                                       | Inline labels on background.                                 |
| `level1`| 8 px shadow, 2 px Y offset                  | List rows, subtle separation.                                |
| `level2`| 16 px shadow, 4 px Y offset                 | Standard glass card lift — default for most surfaces.        |
| `level3`| 24 + 6 px shadow stack                      | Dialogs, popovers, peek-style modal sheets.                  |
| `level4`| 32 px shadow + systemBlue 40 px glow         | Hero surfaces — `IdentityCard`, in-call HUD badges, `DialogImportance.high`. |

### Effects — `app_effects.dart`

| Token                    | Default | When to use                                                       |
|--------------------------|---------|-------------------------------------------------------------------|
| `grainOpacity`           | 0.04    | Default opacity for `GrainOverlay`. "Dusty" feel.                 |
| `grainCellPx`            | 1.5     | Cell size for the noise — balance fine/coarse.                    |
| `scanlineOpacity`        | 0.06    | Per-stripe alpha for `ScanlineOverlay`.                           |
| `scanlineSpacingPx`      | 4       | Vertical pitch between scan-line stripes.                         |
| `scanlineThicknessPx`    | 1       | Stripe thickness — one phosphor row.                              |
| `aberrationDxPx`         | 1.5     | R/B channel split for chromatic-aberration focus state (optional).|

### Haptics — `app_haptics.dart`

The `HapticIntensity` enum is the public vocabulary; the actual platform calls happen in `feedback/stealth_haptics.dart` (Phase 1.3).

| Intensity   | Pattern                              | When to use                                              |
|-------------|--------------------------------------|----------------------------------------------------------|
| `light`     | platform light impact                | Send message, list selection, toggle flip.               |
| `medium`    | platform medium impact               | Call dial, dialog open, voice-record start.              |
| `heavy`     | platform heavy impact                | Hangup, destructive confirmation.                        |
| `success`   | medium → light                       | Save / delivered / key rotation complete.                |
| `warn`      | heavy → light                        | Recoverable issue — retry queued, transient denial.      |
| `error`     | heavy × 2 (80 ms gap)                | Unrecoverable — auth fail, decrypt fail, call drop.      |
| `selection` | selectionClick                       | Segmented control changes, tab swipes, list scrubbing.   |

---

## Signature elements

The "what makes Stealth unmistakably Stealth" pieces. Use these
sparingly — their power comes from being noticed once and felt
afterwards, not from being everywhere.

### `ScanlineOverlay`

`client/lib/themes/apple_liquid/effects/scanline_overlay.dart`

Thin horizontal stripes painted over a child widget. Opacity =
`AppEffects.scanlineOpacity × intensity`.

| Surface                                       | Intensity | Why                                                              |
|-----------------------------------------------|-----------|------------------------------------------------------------------|
| Outgoing chat bubbles (Phase 2.3)             | 0.5       | Signature ownership marker — "this came from your key".          |
| `DialogImportance.high` dialog body (Phase 1.5)| 1.0       | Visual distinction for high-stakes confirmations.                |
| In-call "E2E ENCRYPTED" badge (Phase 7.1)     | 1.0       | The single most identifying moment in the app — make it count.   |

Auto-disables in `Brightness.light`. Pass `force: true` (tests only).

### `GrainOverlay`

`client/lib/themes/apple_liquid/effects/grain_overlay.dart`

Procedural noise painted over a child. Default opacity 0.04 — felt
but not noticed. Deterministic seed → stable across rebuilds and
snapshot tests.

| Surface                                | Opacity | Why                                                  |
|----------------------------------------|---------|------------------------------------------------------|
| Registration screen background (Phase 6.2)| 0.04 | Adds texture to the first impression.                 |
| `StealthEmptyState` background (Phase 1.7)| 0.04 | Empty states become atmospheric rather than blank.    |

Auto-disables in `Brightness.light`.

### Key-fingerprint backdrop (`StealthEmptyState`)

Behind every empty-state icon, a deterministic 14×8 grid of hex
pairs (`A2:5F:90:...`) renders at ~3.5% opacity in `GeistMono`. Seed
is the empty-state `title`, so each surface gets a different but
stable pattern across rebuilds and golden snapshots. Wrapped in
`IgnorePointer` so it never blocks the action button.

Auto-disables in `Brightness.light` (renders as `SizedBox.shrink()`)
— against a near-white scaffold the pattern reads as noise rather
than cryptographic surface, which breaks the "accessibility / high
contrast" intent of light mode.

### `ChromaticAberration`

`client/lib/themes/apple_liquid/effects/chromatic_aberration.dart`

Subtle "RGB-split" colour-fringe effect. Renders the wrapped subtree
once as the interactive baseline, then layers two ghost copies
underneath — a red ghost shifted left and a cyan ghost shifted right
by `AppEffects.aberrationDxPx × intensity`. The result reads as a
camera lens losing focus for a beat.

| Surface                                          | Trigger                              | Why                                                            |
|--------------------------------------------------|--------------------------------------|----------------------------------------------------------------|
| `GlassTextField` focus gain                      | brief 1 → 0 pulse over `AppMotion.normal` | Lens-auto-focus cue when an input takes attention.            |
| (Reserved) `IdentityCard` rotate-key armed state | hold-to-confirm visual               | Future polish — wire when rotate-key UX matures.              |

Auto-disables in `Brightness.light`. Pass `intensity: 0` at rest —
the widget short-circuits to the bare child, so wrapped subtrees pay
no cost while idle. Wrapped in `RepaintBoundary` so the ghosts don't
invalidate sibling subtrees mid-pulse.

### `DecryptText`

`client/lib/themes/apple_liquid/motion/decrypt_text.dart`

Animated cipher-decoded reveal of a string. Each character starts as
a random hex digit (`0-9A-F` default alphabet) and resolves to its
target value at a staggered point along the timeline — reads as
cipher-text decoding into the real string.

| Surface                          | Duration              | Why                                                          |
|----------------------------------|-----------------------|--------------------------------------------------------------|
| Loading screen `STEALTH` wordmark | `AppMotion.slow` (400 ms) | The single most identifying first-impression moment in the app. |
| (Reserved) safety-number reveal  | `AppMotion.slow`      | When user opens Safety Number dialog — future polish.        |

Renders in `GeistMono` so character positions stay stable as letters
resolve (a proportional font would jitter). Respects
`MediaQuery.disableAnimations` — reduce-motion users see the final
string immediately, no scramble frames. Logged once on mount with the
target string so dev builds can verify the animation fires on cold
launch.

### Loading-screen boot-sequence crossfade

`ui/screens/loading_screen.dart` mounts `CircuitBoardBackground`
(the "system coming up" texture) on top of
`StealthAnimatedBackground` (the app's home surface). As the
bootstrap reaches its last step the circuit-board layer fades to 0
over `AppMotion.slow` with `AppMotion.emphasized` easing — the
animated stealth surface emerges from underneath, then a brief beat
later the navigator pushes `MainTabs`. The handoff reads as the
system finishing booting, not as a hard screen swap.

## Performance discipline

Adding overlays (`ScanlineOverlay`, `GrainOverlay`) on top of
already-animated glass surfaces stacks repaint work. Without
isolation, a single animation frame invalidates the whole subtree
above the overlay. On older Android Skia and on the web build this
shows up as dropped frames the moment a user opens chat or a
dialog.

The mitigation is `RepaintBoundary` — Flutter's primitive for
"don't repaint my parent when I change". Add one around any subtree
that has its own animation tick. Cheaper than not adding one when
needed; harmless when wrong.

### Non-negotiable rules

- **Every signature effect** (`ScanlineOverlay`, `GrainOverlay`,
  future `ChromaticAberration`) is wrapped in `RepaintBoundary`
  inside the widget itself. Callers never need to add one.
- **Every item in `StaggeredListView`** is wrapped in
  `RepaintBoundary` by the wrapper — entrance animations don't
  invalidate siblings.
- **`StealthSkeletonTile`** wraps its shimmer in `RepaintBoundary`.
- **`GlassChatBubble`** — when the bubble polish task (Phase 2.3)
  adds the send-confirmed pulse, wrap the bubble in
  `RepaintBoundary`.
- **`StealthAnimatedBackground`** runs a 20-second animation loop;
  wrap it in `RepaintBoundary` so it does not invalidate any
  foreground tree.
- **Any new widget that owns an `AnimationController`** belongs
  inside a `RepaintBoundary`. If you're not sure whether to add
  one, add it.

### How to verify

Toggle `debugRepaintRainbowEnabled = true` in `main.dart` for one
build during development. Tinted regions should:

- change color only when their own contents change;
- NOT flash whenever a sibling animates.

If the whole screen flashes on every snackbar/dialog tick, a
`RepaintBoundary` is missing somewhere up the tree.

## Component inventory

| Component                  | Path                                                                                               | Used in                                              |
|----------------------------|----------------------------------------------------------------------------------------------------|------------------------------------------------------|
| `SectionHeader`            | `themes/apple_liquid/widgets/section_header.dart`                                                  | Settings groups; future Chats/Contacts grouping.     |
| `ListDivider`              | `themes/apple_liquid/widgets/list_divider.dart`                                                    | Replaces inline `Divider` / `SizedBox` separators.   |
| `showStealthSnackBar`      | `themes/apple_liquid/feedback/stealth_snack_bar.dart`                                              | Every feedback toast — Chats, Contacts, Profile, Registration, Settings. |
| `showStealthDialog`        | `themes/apple_liquid/feedback/stealth_dialog.dart`                                                 | Replaces bare `AlertDialog`. Carries `DialogImportance.high` for destructive ops. |
| `StealthHaptics`           | `themes/apple_liquid/feedback/stealth_haptics.dart`                                                | Send / dial / hangup / toggle / dialog confirm.      |
| `StealthLoadingIndicator`  | `themes/apple_liquid/feedback/stealth_loading_indicator.dart`                                      | Replaces bare `CircularProgressIndicator`.           |
| `StealthSkeletonTile`      | `themes/apple_liquid/feedback/stealth_skeleton.dart`                                               | Chats / Contacts loading state.                      |
| `StealthEmptyState`        | `ui/widgets/empty_state.dart`                                                                      | Replaces legacy `EmptyState`; reads `AppColors`.     |
| `GlassPageRoute`           | `themes/apple_liquid/navigation/glass_page_route.dart`                                             | All forward navigation (currently optional).         |
| `StaggeredListView`        | `themes/apple_liquid/motion/staggered_list_view.dart`                                              | Orchestrated first-render reveal for lists.          |
| `ScanlineOverlay`          | `themes/apple_liquid/effects/scanline_overlay.dart`                                                | Outgoing chat bubbles; high-importance dialogs; E2E badge. |
| `GrainOverlay`             | `themes/apple_liquid/effects/grain_overlay.dart`                                                   | Registration background; empty states.               |
| `StatusChip`               | `themes/apple_liquid/widgets/status_chip.dart`                                                     | Diagnostics; call connection-quality readout.        |
| `ChatTile`                 | `themes/apple_liquid/widgets/chats/chat_tile.dart`                                                 | Chats list.                                          |
| `ContactTile`              | `themes/apple_liquid/widgets/contacts/contact_tile.dart`                                           | Contacts grid (wiring deferred — file ready).        |
| `CallHudOverlay`           | `themes/apple_liquid/widgets/call/call_hud_overlay.dart`                                           | In-call HUD (wiring deferred — file ready).          |
| `ThemeController`          | `themes/theme_controller.dart`                                                                     | Settings theme toggle + main bootstrap.              |

## Dual identity (dark vs light)

Dark mode is Stealth's **signature** identity — that's where the
"refined crypto-noir" aesthetic lives. Light mode exists as an
**accessibility / high contrast** mode for users who can't or don't
want to use dark. They are not visual peers.

**Default on fresh install:** `ThemeMode.dark`.

**Backward-compat:** users who already chose a `themeMode`
preference before this refactor (including `system`) keep it. Only
fresh installs (no persisted key) land on dark by default. See
`ThemeController.loadInitial` for the gate.

| Surface / widget               | Behaviour in dark                                         | Behaviour in light                                       |
|--------------------------------|-----------------------------------------------------------|----------------------------------------------------------|
| `ScanlineOverlay`              | Renders scan-lines at `AppEffects.scanlineOpacity`.       | Auto-disables; passes `child` through unchanged.         |
| `GrainOverlay`                 | Renders procedural noise.                                 | Auto-disables.                                           |
| `GlassChatBubble` (outgoing)   | Scan-line overlay at `intensity: 0.5`.                    | No overlay (inherited from `ScanlineOverlay` gating).    |
| `StealthDialog` (high import.) | Scan-line over body.                                      | No overlay.                                              |
| `StealthAnimatedBackground`    | Animated blur spots over stealth gradient.                | Animation controller stopped; static `stealthGradientLight` gradient under the foreground. |
| `GlassContainer`                | Standard glass intensity + full `BackdropFilter` blur.   | Lower-intensity preset (black-tinted film, hairline shadow, no coloured glow); blur sigma halved. |
| `AppColors`                     | Full palette.                                              | Same colour values — high-contrast variants come from native theme contrast, not from re-tokenising. |

Both light-mode tunings (`GlassContainer` lower-intensity preset and
`StealthAnimatedBackground` static-gradient fallback) ship as part of
the widget's own theme-awareness — no caller opt-in required. The
auto-gating of `ScanlineOverlay`, `GrainOverlay`, and future
`ChromaticAberration` covers the signature-moment skips on top of
that.

## Accessibility contract

Every interactive surface in the app — including extracted widgets
introduced by this refactor — must preserve or extend
`client/lib/constants/accessibility_ids.dart`. That file is the
single source of truth for `Semantics` labels and is also consumed
by the out-of-repo Appium test suite. **Do not change values
without coordinating the Appium suite update.**

The design-system v2 refactor added the following labels (see
"Design-system v2 additions" section in `accessibility_ids.dart`):

- `chatTileAvatar`, `chatTileLastMessage`, `chatTileUnreadBadge` — ChatTile internals.
- `contactTileTrailing`, `contactTileVerificationBadge` — ContactTile internals.
- `sectionHeader`, `listDivider` — structural primitives.
- `snackBarMessage`, `snackBarDismiss` — `showStealthSnackBar`.
- `dialogPrimaryAction`, `dialogSecondaryAction`, `dialogDestructiveAction` — `showStealthDialog`.
- `themeToggleSegmented`, `themeToggleLight`, `themeToggleDark`, `themeToggleSystem` — settings toggle.
- `callEncryptedBadge`, `callDurationTimer`, `callConnectionStatus` — `CallHudOverlay`.

Rules for new widgets:

- Wrap every interactive element in `Semantics(label: AccessibilityIds.foo, button: true)`.
- For new constants, add the entry to `accessibility_ids.dart` first; do not inline literal strings.
- When migrating an existing screen, audit every existing `Semantics(...)` block before extracting; port verbatim.
