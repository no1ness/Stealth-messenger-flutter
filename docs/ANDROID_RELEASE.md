# Android Release Guide

How to produce a publishable Stealth Messenger APK / App Bundle.
For day-to-day debug builds see [`../INSTALL_ANDROID.md`](../INSTALL_ANDROID.md).

## Application identity

| Setting       | Value                  | Where                                    |
| ------------- | ---------------------- | ---------------------------------------- |
| `namespace`   | `com.stealth.messenger` | `client/android/app/build.gradle.kts`    |
| `applicationId` | `com.stealth.messenger` | `client/android/app/build.gradle.kts`    |

If you fork the project and ship your own distribution change both
values (and the Play Console listing). The two must stay in sync.

## Release keystore

Release builds are signed via an optional
`client/android/key.properties` file. When the file is absent, the
build falls back to the debug keystore so `flutter run --release`
keeps working locally; but the resulting artifact is **not**
suitable for publication.

### One-time setup

1. Generate a keystore (do this somewhere outside the repo):

   ```bash
   keytool -genkeypair -v \
     -keystore "$HOME/stealth-release.jks" \
     -alias stealth \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

   Pick a strong store password and key password. Store them in a
   password manager — Play Console will not accept a keystore swap
   later.

2. Copy the template:

   ```bash
   cp client/android/key.properties.example client/android/key.properties
   ```

3. Edit `client/android/key.properties` and fill in the four fields:

   ```properties
   storeFile=/home/you/stealth-release.jks
   storePassword=...
   keyAlias=stealth
   keyPassword=...
   ```

   `key.properties` is gitignored. So is `**/*.keystore` / `**/*.jks`.

### Building

```bash
cd client
flutter build apk --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld

# or for Play Console:
flutter build appbundle --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld
```

The build script detects `key.properties` automatically and uses the
release signing config. Verify with:

```bash
keytool -printcert -jarfile \
  build/app/outputs/flutter-apk/app-release.apk | head -20
```

The certificate fingerprint must NOT match the debug keystore
fingerprint shipped with the Android SDK.

## Lint baseline

`app/build.gradle.kts` enables `checkReleaseBuilds = true` so lint
runs as part of every release assembly. `abortOnError` is currently
`false` because the project does not yet ship a `lint-baseline.xml`
checked in. Generate the baseline once and commit it to lock the
current lint surface:

```bash
cd client/android
./gradlew :app:updateLintBaseline
```

After committing the baseline, flip `abortOnError = true` in
`app/build.gradle.kts` so future regressions block the build.

## Verifying the release

After the build completes:

1. Install the APK on a clean profile / second device.
2. Confirm the app advertises `applicationId=com.stealth.messenger`
   (e.g. `adb shell pm list packages | grep stealth`).
3. Trigger a real call through the configured PocketBase signaling
   server to make sure `--dart-define` overrides reached the runtime.
4. Run `flutter symbolize` against any obfuscated stack traces if
   crashes occur — the release build uses Flutter's standard symbol
   stripping.
