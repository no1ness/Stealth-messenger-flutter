[← PocketBase Setup](pocketbase-setup.md) · [Back to README](../README.md) · [Тестирование →](testing.md)

# Android Release Guide

Как собрать publishable Stealth Messenger APK / App Bundle.
Для debug-сборок см. [Начало работы](getting-started.md).

## Application identity

| Setting | Value | Файл |
|---------|-------|------|
| `namespace` | `com.stealth.messenger` | `client/android/app/build.gradle.kts` |
| `applicationId` | `com.stealth.messenger` | `client/android/app/build.gradle.kts` |

При форке измените оба значения (и Play Console listing).

## Release keystore

Release-сборки подписываются через `client/android/key.properties`.
Без него build использует debug keystore — **не для публикации**.

### Одноразовая настройка

1. Сгенерируйте keystore (вне репозитория):

   ```bash
   keytool -genkeypair -v \
     -keystore "$HOME/stealth-release.jks" \
     -alias stealth \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Скопируйте шаблон:

   ```bash
   cp client/android/key.properties.example client/android/key.properties
   ```

3. Заполните `client/android/key.properties`:

   ```properties
   storeFile=/home/you/stealth-release.jks
   storePassword=...
   keyAlias=stealth
   keyPassword=...
   ```

   `key.properties` находится в `.gitignore`.

### Сборка

```bash
cd client

# APK
flutter build apk --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld

# App Bundle (для Play Console)
flutter build appbundle --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld
```

Проверка подписи:

```bash
keytool -printcert -jarfile \
  build/app/outputs/flutter-apk/app-release.apk | head -20
```

## Lint baseline

`app/build.gradle.kts` включает `checkReleaseBuilds = true`.
`abortOnError` пока `false` — нет закоммиченного `lint-baseline.xml`.

Генерация baseline:

```bash
cd client/android
./gradlew :app:updateLintBaseline
```

После коммита baseline переключите `abortOnError = true`.

## Верификация release

1. Установите APK на чистый профиль / второе устройство
2. Проверьте `applicationId`: `adb shell pm list packages | grep stealth`
3. Совершите звонок через PocketBase signaling
4. При крашах: `flutter symbolize` для obfuscated stack traces

## See Also

- [Начало работы](getting-started.md) — debug-сборка и установка
- [Конфигурация](configuration.md) — `--dart-define` для production
- [Тестирование](testing.md) — верификация после сборки
