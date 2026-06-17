[← Bypass Setup](BYPASS_SETUP.md) · [Back to README](../README.md) · [Deployment →](deployment.md)

# Гайд по Android Release-сборке

Как собрать публикабельный Stealth Messenger APK / App Bundle.
Для повседневных debug-сборок см. [`../INSTALL_ANDROID.md`](../INSTALL_ANDROID.md).

## Идентичность приложения

| Параметр        | Значение                | Где                                       |
| --------------- | ----------------------- | ----------------------------------------- |
| `namespace`     | `com.stealth.messenger` | `client/android/app/build.gradle.kts`     |
| `applicationId` | `com.stealth.messenger` | `client/android/app/build.gradle.kts`     |

Если форкнул проект и хочешь публиковать собственный дистрибутив —
поменяй оба значения (и листинг в Play Console). Оба должны быть синхронны.

## Release keystore

Release-сборки подписываются опциональным файлом
`client/android/key.properties`. Если файла нет, сборка откатывается на
debug-keystore, чтобы `flutter run --release` продолжал работать
локально — но артефакт **не подходит** для публикации.

### Одноразовая настройка

1. Сгенерируй keystore (где-нибудь вне репо):

   ```bash
   keytool -genkeypair -v \
     -keystore "$HOME/stealth-release.jks" \
     -alias stealth \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

   Выбери надёжные store password и key password. Сохрани их в
   менеджере паролей — Play Console не позволит позже подменить keystore.

2. Скопируй шаблон:

   ```bash
   cp client/android/key.properties.example client/android/key.properties
   ```

3. Отредактируй `client/android/key.properties` и заполни четыре поля:

   ```properties
   storeFile=/home/you/stealth-release.jks
   storePassword=...
   keyAlias=stealth
   keyPassword=...
   ```

   `key.properties` gitignored. То же касается `**/*.keystore` / `**/*.jks`.

### Сборка

```bash
cd client
flutter build apk --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld

# или для Play Console:
flutter build appbundle --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld
```

Build-скрипт автоматически детектит `key.properties` и использует
release signing config. Проверь подпись:

```bash
keytool -printcert -jarfile \
  build/app/outputs/flutter-apk/app-release.apk | head -20
```

Fingerprint сертификата **не должен** совпадать с fingerprint
debug-keystore из Android SDK.

## Lint baseline

`app/build.gradle.kts` ставит `checkReleaseBuilds = true`, поэтому lint
гоняется при каждой release-сборке. В репозитории уже есть
`client/android/app/lint-baseline.xml`, а `abortOnError = true` блокирует
новые Android lint-регрессии поверх baseline.

Если намеренно обновляешь baseline после исправления/пересмотра lint-surface:

```bash
cd client/android
./gradlew :app:updateLintBaseline
```

Коммить обновлённый baseline нужно вместе с изменением, которое объясняет
новую lint-поверхность.

## Проверка release-сборки

После сборки:

1. Установи APK на чистый профиль / второе устройство.
2. Подтверди что приложение объявляет `applicationId=com.stealth.messenger`
   (например `adb shell pm list packages | grep stealth`).
3. Совершишь реальный звонок через настроенный PocketBase signaling
   сервер, чтобы убедиться что `--dart-define` overrides доехали до runtime.
4. Если возникают краши с обфусцированными стектрейсами —
   `flutter symbolize`. Release-сборка использует стандартный
   symbol stripping от Flutter.

## CI release-сборки (task #13)

Отдельный job `build-android-release` в `.github/workflows/ci.yml`
выпускает подписанные APK + AAB ночью (`03:00 UTC`) и по запросу
(`gh workflow run ci.yml`). Job **гейтнут на четырёх секретах** —
все должны быть проставлены в настройках GitHub репозитория; если
хотя бы одного нет, job пропускается с аннотацией `notice` (PR от
форков не падают):

| Секрет                    | Назначение                                          |
| ------------------------- | --------------------------------------------------- |
| `ANDROID_KEYSTORE_BASE64` | Keystore `stealth-release.jks`, закодированный в `base64`. |
| `ANDROID_STORE_PASSWORD`  | Пароль keystore.                                    |
| `ANDROID_KEY_ALIAS`       | Алиас ключа внутри keystore (обычно `stealth`).     |
| `ANDROID_KEY_PASSWORD`    | Пароль ключа внутри keystore.                       |

Что делает job:

1. Декодирует keystore в `$RUNNER_TEMP/stealth-release.jks`.
2. Пишет `client/android/key.properties` из остальных трёх секретов.
3. Запускает `flutter build apk --release` и `flutter build appbundle --release` —
   оба опираются на уже существующее signing-wiring в
   `client/android/app/build.gradle.kts`.
4. Загружает оба артефакта (`android-release`, хранится 14 дней).

Рядом есть sibling-job `analyze-macos` на `04:00 UTC` (и
`workflow_dispatch`), который гоняет `flutter analyze` + `flutter test`
на `macos-latest`. В PR-матрице его НЕТ — это сохраняет короткий
PR cycle time.

## See Also

- [Deployment](deployment.md) — деплой и CI/CD
- [Architecture](ARCHITECTURE.md) — обзор системы
- [PocketBase Setup](POCKETBASE_SETUP.md) — развёртывание signaling-сервера
