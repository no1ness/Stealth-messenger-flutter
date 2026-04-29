# Установка Stealth Messenger на Android

## Способ 1: Сборка APK (рекомендуется)

### Предварительные требования:
- Flutter SDK установлен и добавлен в PATH
- Android SDK установлен
- Телефон подключен по USB с включенной отладкой по USB

### Шаги:

#### 1. Проверка окружения
```bash
flutter doctor
```

Убедитесь что:
- ✅ Flutter установлен
- ✅ Android toolchain установлен
- ✅ Android Studio / Android SDK доступны

#### 2. Подключение телефона
```bash
# Включите на телефоне: Настройки → О телефоне → 7 раз нажать "Номер сборки"
# Затем: Настройки → Для разработчиков → Отладка по USB (включить)

# Проверьте что телефон виден:
flutter devices
# или
adb devices
```

Должно показать ваше устройство, например:
```
List of devices attached
ABC123XYZ       device
```

#### 3. Сборка и установка APK

**Вариант A: Прямая установка на подключенный телефон**
```bash
cd client
flutter run --release
```

**Вариант B: Сборка APK файла**
```bash
cd client
flutter build apk --release
```

APK будет создан в:
```
client/build/app/outputs/flutter-apk/app-release.apk
```

Размер: ~50-80 MB

#### 4. Установка APK на телефон

**Способ 1: Через ADB**
```bash
adb install client/build/app/outputs/flutter-apk/app-release.apk
```

**Способ 2: Копирование файла**
1. Скопируйте `app-release.apk` на телефон (через USB, облако, мессенджер)
2. Откройте файл на телефоне
3. Разрешите установку из неизвестных источников (если попросит)
4. Нажмите "Установить"

---

## Способ 2: Сборка App Bundle (для Google Play)

Если планируете публиковать в Google Play:

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

Отредактируйте `client/android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    applicationId = "com.stealth.messenger"  // ← измените на свой
    minSdk = 21
    targetSdk = 34
    versionCode = 1
    versionName = "0.1.0"
}
```

### 2. Настроить .env файл

Создайте `client/.env` с вашими Supabase credentials:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your-username
TURN_PASSWORD=your-password
```

### 3. Подписать APK (для production)

Для production-сборки нужно создать keystore:

```bash
keytool -genkey -v -keystore ~/stealth-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias stealth
```

Создайте `client/android/key.properties`:
```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=stealth
storeFile=/path/to/stealth-release-key.jks
```

Обновите `client/android/app/build.gradle.kts`:
```kotlin
// Добавьте перед android {}
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...
    
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

---

## Проверка установки

После установки:

1. Откройте приложение "Stealth" на телефоне
2. Введите никнейм
3. Нажмите "GET STARTED"
4. Приложение должно загрузиться и показать главный экран с табами

---

## Устранение проблем

### Ошибка: "Flutter not found"
```bash
# Добавьте Flutter в PATH:
# Windows (PowerShell):
$env:Path += ";C:\path\to\flutter\bin"

# Или добавьте постоянно через Системные переменные
```

### Ошибка: "Android SDK not found"
```bash
# Установите Android SDK через Android Studio
# Или установите command-line tools:
# https://developer.android.com/studio#command-tools
```

### Ошибка: "device not found"
```bash
# Проверьте USB-отладку:
adb devices

# Если "unauthorized" — разрешите отладку на телефоне
# Если не видит — переподключите USB, попробуйте другой кабель
```

### Ошибка при сборке: "Execution failed for task ':app:lintVitalAnalyzeRelease'"
```bash
# Отключите lint проверки (временно):
# В android/app/build.gradle.kts добавьте:
android {
    lintOptions {
        checkReleaseBuilds = false
        abortOnError = false
    }
}
```

### Приложение крашится при запуске
```bash
# Проверьте логи:
adb logcat | grep -i flutter

# Убедитесь что .env файл присутствует и содержит корректные данные
```

---

## Размер APK

- **Debug APK:** ~80-100 MB
- **Release APK:** ~50-70 MB
- **Release APK (split-per-abi):** ~20-30 MB на архитектуру

Для уменьшения размера используйте split APKs:
```bash
flutter build apk --release --split-per-abi
```

Это создаст отдельные APK для:
- `app-armeabi-v7a-release.apk` (32-bit ARM)
- `app-arm64-v8a-release.apk` (64-bit ARM)
- `app-x86_64-release.apk` (64-bit x86)

Установите тот, который подходит для вашего телефона (обычно arm64-v8a).

---

## Быстрая команда (всё в одном)

```bash
# 1. Перейти в папку проекта
cd client

# 2. Проверить устройства
flutter devices

# 3. Собрать и установить на подключенный телефон
flutter run --release

# Или собрать APK
flutter build apk --release --split-per-abi

# Установить конкретный APK
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

**Готово!** Приложение установлено на телефон. Теперь можно протестировать реальные звонки, передачу файлов и изображений на реальном устройстве.
