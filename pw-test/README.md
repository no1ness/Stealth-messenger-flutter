# pw-test — E2E scripts

End-to-end test scripts driving the Stealth client through real browsers
(Playwright) and physical/emulated Android devices (Appium). Run from the
repository root.

## Contact-bundle rule (CI-enforced)

Stealth is local-first: contacts can only be added via a **contact bundle**
(`stealth:<base64url(JSON)>` carrying `userId`, `nickname`, AND
`publicKey`). Raw user IDs are no longer accepted by the client because
E2E encryption requires the peer's public key up-front.

Any `pw-test/*.mjs` script that calls `addContact(...)` MUST resolve the
bundle through one of:

- `readContactBundle(page)` from [`./contact-bundle-helper.mjs`](./contact-bundle-helper.mjs) — the canonical helper for Playwright/web flows;
- a per-file internal helper (e.g. `getContactBundle()` in
  `appium-call-test.mjs`) that returns a `stealth:` prefixed string;
- a literal `"stealth:..."` value (rare; used for fixed-fixture tests).

Passing a bare UUID is forbidden and fails the [`lint-contact-bundle`](./lint-contact-bundle.mjs)
CI job (`pw-test-lint` in `.github/workflows/ci.yml`).
