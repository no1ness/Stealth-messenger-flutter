# Design Mockups

Visual companion to [`docs/design-system.md`](../design-system.md).

Each file is a self-contained HTML page. No build step — open
`index.html` in any modern browser (Chromium / Firefox / Safari).
The shared `_tokens.css` mirrors the Flutter constants in
`client/lib/themes/apple_liquid/constants/`. When a value drifts,
the Flutter side is authoritative.

## Pages

| File              | Surface                                                            |
|-------------------|--------------------------------------------------------------------|
| `index.html`      | Gallery overview — start here.                                     |
| `chats.html`      | Chats list: ChatTile, mono timestamps, glass nav bar.              |
| `in-call.html`    | In-call HUD: signature E2E ENCRYPTED badge + mono duration.        |
| `effects.html`    | All six signature effects on the same sample (scanline, grain, fingerprint, chromatic aberration, decrypt-text, boot-sequence crossfade). |
| `empty-state.html`| Empty state with the key-fingerprint backdrop + grain.             |
| `tokens.html`     | Complete visible inventory: colour, type, spacing, motion, elevation, effects, haptics. |

## Conventions

- **Fonts.** Geist + Geist Mono, loaded via Google Fonts CDN
  inside `_tokens.css`. Matches the OFL 1.1 families bundled in
  `client/assets/fonts/`.
- **Palette.** Refined crypto-noir: `#0A0E1A` canvas + `#151922`
  cards + a single sharp `#007AFF` accent. Dual-identity light
  mode is intentionally out of scope here — these mockups are the
  signature dark identity.
- **Effect parity.** Scan-line, grain, key-fingerprint, chromatic
  aberration and a decrypt-text approximation are reproduced in
  CSS where possible. The Flutter widgets are the authoritative
  implementation; the mockups exist to show how the effects
  *should land* on a real surface.
- **No JavaScript** except where strictly needed (DecryptText
  preview cycle is done with CSS `steps()` for portability).

## Updating

1. Touch the constants in `client/lib/themes/apple_liquid/constants/`.
2. Mirror the same changes in `_tokens.css`.
3. Touch the affected mockup pages if the new value changes how a
   surface reads.
4. Cross-link the surface from `docs/design-system.md` if a new
   signature element ships.

## Out of scope

- Light-mode variants — see the "Dual identity" section of
  `docs/design-system.md`.
- Pixel-perfect 1:1 reproduction of the Flutter output.
  CSS rasterisation differs from Skia; treat these as design
  intent, not as a render contract.
- Visual reel goldens — those live under `client/test/golden/`
  and are produced by the Flutter test runner.
