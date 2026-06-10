# App Updates

Stealth supports a simple Android APK update flow that does not use Play Store or App Store APIs. The app reads a static HTTPS manifest, compares the published version with the installed build, downloads the APK after the user presses **Update now**, verifies the SHA-256 digest, and hands the file to Android's system package installer.

This update metadata is release delivery metadata only. It is not a backend for contacts, messages, attachments, call history, analytics, or any other user data.

## User-Facing Behavior

- Startup loading shows the installed app version, for example `Stealth 0.1.0+1`.
- If `APP_UPDATE_MANIFEST_URL` is unset, update checks are disabled and app startup continues normally.
- If the manifest is unreachable or invalid, the app logs the failure and continues startup normally.
- Optional updates show an **Update available** prompt with **Update now** and **Not now**.
- Mandatory updates show an **Update required** prompt with **Update now** only.
- Settings includes an **Updates** card with the current version, update status, manual **Check for updates**, and **Update now** when an update is available.

## Configuration

Set the update manifest URL at build time:

```bash
flutter build apk \
  --dart-define=POCKETBASE_URL=https://signal.your.tld \
  --dart-define=APP_UPDATE_MANIFEST_URL=https://updates.your.tld/stealth/manifest.json
```

For local development, `client/.env.defaults` also contains `APP_UPDATE_MANIFEST_URL=`. Leave it blank to disable update checks.

The manifest URL must be absolute HTTPS. HTTP URLs are rejected.

## Manifest Schema

```json
{
  "version": "0.2.0",
  "buildNumber": 2,
  "apkUrl": "https://updates.your.tld/stealth/stealth-0.2.0+2.apk",
  "sha256": "64-character-lowercase-hex-sha256",
  "mandatory": false,
  "releaseNotes": "Short release notes shown in the update prompt."
}
```

Fields:

- `version`: semantic app version string.
- `buildNumber`: non-negative integer build number.
- `apkUrl`: absolute HTTPS URL to the APK file.
- `sha256`: SHA-256 digest of the APK as 64 lowercase hex characters.
- `mandatory`: `true` blocks the skip action in the startup prompt.
- `releaseNotes`: user-facing release notes.

## Release Process

1. Build a signed release APK with an incremented `version` / `buildNumber`.

```bash
flutter build apk --release --build-name=0.2.0 --build-number=2
```

2. Compute the APK checksum.

```bash
sha256sum build/app/outputs/flutter-apk/app-release.apk
```

3. Upload the APK to an HTTPS host.

4. Publish or update the static manifest JSON with the new version, build number, APK URL, checksum, mandatory flag, and release notes.

5. Open the existing app and confirm the startup prompt or Settings **Check for updates** finds the release.

## Android Install Flow

The app downloads the APK into its cache directory, verifies the manifest SHA-256, and calls a Flutter platform channel named `stealth/app_update`. Android then exposes the APK through a `FileProvider` and starts `Intent.ACTION_VIEW` with MIME type `application/vnd.android.package-archive`.

Android still requires explicit user confirmation in the system installer. Silent install is not supported.

## Logging

Relevant log prefixes:

- `[app-update]`: manifest checks, current/latest versions, download progress, checksum verification, installer handoff.
- `[app-update.ui]`: startup prompt display, skip action, update button, update errors.
- `[settings.ui]`: manual Settings update checks and install requests.

Use verbose logging during development:

```bash
flutter run --dart-define=STEALTH_LOG_LEVEL=debug
```

Do not log signed URLs with query tokens. The implementation logs only safe URI labels and structured status details.

## Troubleshooting

- **No update prompt appears:** ensure `APP_UPDATE_MANIFEST_URL` is set and points to HTTPS.
- **Status says update checks are not configured:** the manifest URL is blank.
- **Status says update check failed:** inspect `[app-update]` logs for manifest parse, network, or HTTPS validation errors.
- **Download succeeds but install does not start:** verify Android allows installing unknown apps for Stealth and check `[app-update] install handoff failed` logs.
- **Checksum mismatch:** re-run `sha256sum` on the uploaded APK and update the manifest.
- **Non-Android platform:** APK install is unsupported; the app should show an unsupported state instead of failing.
