# Установка Stealth Messenger на Android

## Способ 1: Сборка APK (рекомендуется)

### Предварительные требования

- Flutter SDK установлен и добавлен в `PATH`
- Android SDK установлен
- Телефон подключён по USB с включённой USB-отладкой

### Шаги

#### 1. Проверка окружения

```bash
flutter doctor
```

Убедись что:

- ✅ Flutter установлен
- ✅ Android toolchain установлен
- ✅ Android Studio / Android SDK доступны

#### 2. Подключение телефона

```bash
# На телефоне: Настройки → О телефоне → 7 раз нажать "Номер сборки"
# Затем: Настройки → Для разработчиков → USB-отладка (включить)

# Проверь что устройство видно:
flutter devices
# или
adb devices
```

Должно показать твоё устройство, например:

```
List of devices attached
ABC123XYZ       device
```

#### 3. Сборка и установка APK

**Вариант A — прямой запуск на подключённом телефоне:**

```bash
cd client
flutter run --release
```

**Вариант B — собрать APK-файл:**

```bash
cd client
flutter build apk --release
```

APK будет создан в:

```
client/build/app/outputs/flutter-apk/app-release.apk
```

Размер: ~50–80 MB.

#### 4. Установка APK на телефон

**Способ 1 — через ADB:**

```bash
adb install client/build/app/outputs/flutter-apk/app-release.apk
```

**Способ 2 — копирование файла вручную:**

1. Скопируй `app-release.apk` на телефон (USB, облако, мессенджер).
2. Открой файл на телефоне.
3. Разреши установку из неизвестных источников если попросит.
4. Нажми «Установить».

---

## Способ 2: Сборка App Bundle (для Google Play)

Если планируешь публиковать в Google Play:

```bash
cd client
flutter build appbundle --release
```

Файл будет создан в:

```
client/build/app/outputs/bundle/release/app-release.aab
```

---

## Настройка перед сборкой

### 1. Изменить Application ID (опционально)

Отредактируй `client/android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    applicationId = "com.stealth.messenger"  // ← поменяй на свой
    minSdk = 21
    targetSdk = 34
    versionCode = 1
    versionName = "0.1.0"
}
```

### 2. Настроить `.env` файл

Создай `client/.env` с настройками PocketBase / TURN:

```env
POCKETBASE_URL=https://signal.example.com
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your-username
TURN_PASSWORD=your-password
TURNS_URL=turns:your-turn-server.com:443?transport=tcp
TURNS_USERNAME=your-username
TURNS_PASSWORD=your-password
```

### 3. Подписать APK (для production)

Полный гайд по release-подписи — в [`docs/ANDROID_RELEASE.md`](docs/ANDROID_RELEASE.md).
Краткая выжимка:

```bash
keytool -genkeypair -v \
  -keystore "$HOME/stealth-release.jks" \
  -alias stealth \
  -keyalg RSA -keysize 2048 -validity 10000
```

Создай `client/android/key.properties` (gitignored):

```properties
storeFile=/home/you/stealth-release.jks
storePassword=...
keyAlias=stealth
keyPassword=...
```

Подключение `key.properties` уже встроено в `client/android/app/build.gradle.kts` —
release-сборка сама подхватит подпись если файл присутствует. Если файла нет,
release-сборка падает обратно на debug-keystore (для локальной разработки;
**не подходит** для публикации).

---

## Проверка установки

После установки:

1. Открой приложение «Stealth» на телефоне.
2. Введи ник.
3. Нажми **«GET STARTED»**.
4. Приложение должно загрузиться и показать главный экран с табами.

---

## Устранение проблем

### Ошибка: `Flutter not found`

```bash
# Добавь Flutter в PATH:
# Windows (PowerShell):
$env:Path += ";C:\path\to\flutter\bin"

# Или добавь постоянно через системные переменные среды.
```

### Ошибка: `Android SDK not found`

```bash
# Установи Android SDK через Android Studio
# или установи command-line tools:
# https://developer.android.com/studio#command-tools
```

### Ошибка: `device not found`

```bash
# Проверь USB-отладку:
adb devices

# Если "unauthorized" — разреши отладку на телефоне.
# Если устройство не видно — переподключи USB, попробуй другой кабель.
```

### Ошибка сборки: `Execution failed for task ':app:lintVitalAnalyzeRelease'`

Подробно см. [`docs/ANDROID_RELEASE.md`](docs/ANDROID_RELEASE.md) (раздел Lint baseline).
Быстрый workaround — собрать lint baseline:

```bash
cd client/android
./gradlew :app:updateLintBaseline
```

Закомитить полученный `lint-baseline.xml` и пересобрать.

### Приложение крашится при запуске

```bash
# Проверь логи:
adb logcat | grep -i flutter

# Убедись что .env файл присутствует и содержит корректные данные
# (минимум — POCKETBASE_URL).
```

---

## Размер APK

- **Debug APK:** ~80–100 MB
- **Release APK:** ~50–70 MB
- **Release APK (split-per-abi):** ~20–30 MB на архитектуру

Для уменьшения размера используй split APK:

```bash
flutter build apk --release --split-per-abi
```

Это создаст отдельные APK для:

- `app-armeabi-v7a-release.apk` (32-bit ARM)
- `app-arm64-v8a-release.apk` (64-bit ARM)
- `app-x86_64-release.apk` (64-bit x86)

Установи тот, который подходит твоему телефону (обычно `arm64-v8a`).

---

## Быстрая команда (всё в одном)

```bash
# 1. Перейти в папку клиента
cd client

# 2. Проверить устройства
flutter devices

# 3. Собрать и установить на подключённый телефон
flutter run --release

# Или собрать APK
flutter build apk --release --split-per-abi

# Установить конкретный APK
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

**Готово.** Приложение установлено. Теперь можно протестировать звонки,
передачу файлов и изображений на реальном устройстве.
