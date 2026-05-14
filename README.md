# Stealth Messenger

[![CI](https://github.com/no1ness/Stealth-messenger-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/no1ness/Stealth-messenger-flutter/actions/workflows/ci.yml)

Local-first Flutter messenger with E2E-encrypted chats, attachments and
WebRTC peer-to-peer calls. PocketBase is used purely as a transient
signaling relay for `offer / answer / candidate / hangup` — message
history, contacts and attachments never leave the device.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — system overview
- [`docs/SECURITY.md`](docs/SECURITY.md) — threat model and crypto
- [`docs/POCKETBASE_SETUP.md`](docs/POCKETBASE_SETUP.md) — signaling
  server deployment
- [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md) — Android build
- [`AGENTS.md`](AGENTS.md) — baseline rules for AI assistants

## Quality gates

The [`CI workflow`](.github/workflows/ci.yml) runs on every push and pull
request and gates merges on:

| Job                | What it does                                         |
| ------------------ | ---------------------------------------------------- |
| `analyze + test`   | `flutter pub get`, `flutter analyze`, `flutter test` |
| `build web`        | `flutter build web --release`                        |
| `build android`    | `flutter build apk --debug` (JDK 17)                 |
| `signaling smoke`  | End-to-end PocketBase smoke test (optional secret)   |

The optional signaling smoke test runs only when the
`POCKETBASE_TEST_URL` repository secret is configured; without it the
job exits with a `notice` annotation and stays green.

## Project layout

- `client/` — Flutter app source and tests
- `docs/` — long-form documentation
- `pw-test/` — Appium / WebRTC integration scripts
- `.ai-factory/` — internal planning / rules / patches artifacts
