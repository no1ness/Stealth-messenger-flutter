# Diagnostics & Logs screen

In-app screen for inspecting recent log entries and live service health,
plus one-tap export of a redacted diagnostics report to any system share
target (Telegram, Signal, mail, ...).

## How to open

Settings → **Open diagnostics & logs**.

The screen is owned by its own state — closing it tears down the
periodic health-snapshot timer. Opening and closing repeatedly does not
leak resources.

## What you see

### Services

Five live health rows refresh every 5 seconds:

| id            | Source                                                                | OK condition                                                         |
| ------------- | --------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `database`    | `DashboardService.getDashboardSummary()['secureStorageReady']`        | Local secure storage is initialised                                  |
| `attachments` | `AttachmentService.getStorageDebugSummary()['fileCount']`             | Always OK if the call returns (count is informational)               |
| `identity`    | `IdentityService.getUserId()`                                         | A user id is present (registered)                                    |
| `p2p`         | `P2PService.instance.retryWorkerRunning` + `activeChannelCount`       | Retry worker has started                                             |
| `pocketbase`  | `dotenv.env['POCKETBASE_URL']` (read directly to avoid singleton)     | Env var is set and parses to a host                                  |

A failing source is rendered as its own ERROR row with the exception
message — other sources are unaffected.

### Recent logs

Backed by an in-memory ring buffer (capacity 500) inside
`Logger`. The buffer captures every log line ahead of the
`currentLevel` console guard, so WARN/ERROR are always available even on
a release build with the console set to INFO.

Filter chips:
- **All** — DEBUG and above
- **Warnings** — WARN and above (default)
- **Errors** — ERROR only

Tap the refresh icon in the AppBar to re-pull the snapshot. Snapshot is
cached in widget state — list scrolling does not re-read the buffer.

## Share logs

The bottom button assembles a text report and hands it to the system
share sheet via `share_plus`:

- Android / iOS — writes `stealth-diagnostics-<utc-iso>.txt` to the
  app's temporary directory and shares the file. Old reports are
  best-effort cleaned up before writing a new one.
- Web — `Share.share(text)` (no filesystem on web).
- Any failure or user dismiss → falls back to copying the report to the
  clipboard and showing `Copied to clipboard`.

### Redaction policy

The exported text passes through `scrubInlineSensitive`
(`lib/services/diagnostics/log_scrubber.dart`) before being added to the
report. This is **separate from** the existing extras-key redaction in
`Logger`: if a call site interpolates a UUID/PocketBase id/base64 public
key directly into the message text, the inline scrubber still catches it
on export, so users don't leak identifiers when sharing the report.

Patterns matched (best-effort):
- UUID v4 (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- 15-character PocketBase record id (with a heuristic filter — requires
  at least one digit and one letter, to avoid eating common 15-letter
  words)
- Base64-shaped 42-44 character runs (X25519 / ed25519 public keys), also
  filtered by an entropy heuristic

The redaction marker is `…NNNN` (last four characters). It mirrors the
shape produced by `Logger.redactId` in `lib/logging/logger.dart`.

## Files

- `lib/services/diagnostics/diagnostics_service.dart` — health aggregator
  with provider-closure DI for testability
- `lib/services/diagnostics/service_status.dart` — `ServiceStatus`
  value-class
- `lib/services/diagnostics/diagnostics_report.dart` — composer
- `lib/services/diagnostics/log_scrubber.dart` — inline scrubber
- `lib/services/diagnostics/diagnostics_share.dart` — share intent +
  clipboard fallback
- `lib/services/diagnostics/app_environment_info.dart` — env snapshot
  for the report header
- `lib/logging/log_buffer.dart` — in-memory log ring buffer
- `lib/ui/screens/diagnostics/` — `DiagnosticsScreen` + tile widgets
- `lib/local_app_service.dart` — `createDiagnostics()` factory method
- `lib/p2p_service.dart` — `activeChannelCount` and `retryWorkerRunning`
  health getters
