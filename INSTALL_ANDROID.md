# РЈСЃС‚Р°РЅРѕРІРєР° Stealth Messenger РЅР° Android

## РЎРїРѕСЃРѕР± 1: РЎР±РѕСЂРєР° APK (СЂРµРєРѕРјРµРЅРґСѓРµС‚СЃСЏ)

### РџСЂРµРґРІР°СЂРёС‚РµР»СЊРЅС‹Рµ С‚СЂРµР±РѕРІР°РЅРёСЏ:
- Flutter SDK СѓСЃС‚Р°РЅРѕРІР»РµРЅ Рё РґРѕР±Р°РІР»РµРЅ РІ PATH
- Android SDK СѓСЃС‚Р°РЅРѕРІР»РµРЅ
- РўРµР»РµС„РѕРЅ РїРѕРґРєР»СЋС‡РµРЅ РїРѕ USB СЃ РІРєР»СЋС‡РµРЅРЅРѕР№ РѕС‚Р»Р°РґРєРѕР№ РїРѕ USB

### РЁР°РіРё:

#### 1. РџСЂРѕРІРµСЂРєР° РѕРєСЂСѓР¶РµРЅРёСЏ
```bash
flutter doctor
```

РЈР±РµРґРёС‚РµСЃСЊ С‡С‚Рѕ:
- вњ… Flutter СѓСЃС‚Р°РЅРѕРІР»РµРЅ
- вњ… Android toolchain СѓСЃС‚Р°РЅРѕРІР»РµРЅ
- вњ… Android Studio / Android SDK РґРѕСЃС‚СѓРїРЅС‹

#### 2. РџРѕРґРєР»СЋС‡РµРЅРёРµ С‚РµР»РµС„РѕРЅР°
```bash
# Р’РєР»СЋС‡РёС‚Рµ РЅР° С‚РµР»РµС„РѕРЅРµ: РќР°СЃС‚СЂРѕР№РєРё в†’ Рћ С‚РµР»РµС„РѕРЅРµ в†’ 7 СЂР°Р· РЅР°Р¶Р°С‚СЊ "РќРѕРјРµСЂ СЃР±РѕСЂРєРё"
# Р—Р°С‚РµРј: РќР°СЃС‚СЂРѕР№РєРё в†’ Р”Р»СЏ СЂР°Р·СЂР°Р±РѕС‚С‡РёРєРѕРІ в†’ РћС‚Р»Р°РґРєР° РїРѕ USB (РІРєР»СЋС‡РёС‚СЊ)

# РџСЂРѕРІРµСЂСЊС‚Рµ С‡С‚Рѕ С‚РµР»РµС„РѕРЅ РІРёРґРµРЅ:
flutter devices
# РёР»Рё
adb devices
```

Р”РѕР»Р¶РЅРѕ РїРѕРєР°Р·Р°С‚СЊ РІР°С€Рµ СѓСЃС‚СЂРѕР№СЃС‚РІРѕ, РЅР°РїСЂРёРјРµСЂ:
```
List of devices attached
ABC123XYZ       device
```

#### 3. РЎР±РѕСЂРєР° Рё СѓСЃС‚Р°РЅРѕРІРєР° APK

**Р’Р°СЂРёР°РЅС‚ A: РџСЂСЏРјР°СЏ СѓСЃС‚Р°РЅРѕРІРєР° РЅР° РїРѕРґРєР»СЋС‡РµРЅРЅС‹Р№ С‚РµР»РµС„РѕРЅ**
```bash
cd client
flutter run --release
```

**Р’Р°СЂРёР°РЅС‚ B: РЎР±РѕСЂРєР° APK С„Р°Р№Р»Р°**
```bash
cd client
flutter build apk --release
```

APK Р±СѓРґРµС‚ СЃРѕР·РґР°РЅ РІ:
```
client/build/app/outputs/flutter-apk/app-release.apk
```

Р Р°Р·РјРµСЂ: ~50-80 MB

#### 4. РЈСЃС‚Р°РЅРѕРІРєР° APK РЅР° С‚РµР»РµС„РѕРЅ

**РЎРїРѕСЃРѕР± 1: Р§РµСЂРµР· ADB**
```bash
adb install client/build/app/outputs/flutter-apk/app-release.apk
```

**РЎРїРѕСЃРѕР± 2: РљРѕРїРёСЂРѕРІР°РЅРёРµ С„Р°Р№Р»Р°**
1. РЎРєРѕРїРёСЂСѓР№С‚Рµ `app-release.apk` РЅР° С‚РµР»РµС„РѕРЅ (С‡РµСЂРµР· USB, РѕР±Р»Р°РєРѕ, РјРµСЃСЃРµРЅРґР¶РµСЂ)
2. РћС‚РєСЂРѕР№С‚Рµ С„Р°Р№Р» РЅР° С‚РµР»РµС„РѕРЅРµ
3. Р Р°Р·СЂРµС€РёС‚Рµ СѓСЃС‚Р°РЅРѕРІРєСѓ РёР· РЅРµРёР·РІРµСЃС‚РЅС‹С… РёСЃС‚РѕС‡РЅРёРєРѕРІ (РµСЃР»Рё РїРѕРїСЂРѕСЃРёС‚)
4. РќР°Р¶РјРёС‚Рµ "РЈСЃС‚Р°РЅРѕРІРёС‚СЊ"

---

## РЎРїРѕСЃРѕР± 2: РЎР±РѕСЂРєР° App Bundle (РґР»СЏ Google Play)

Р•СЃР»Рё РїР»Р°РЅРёСЂСѓРµС‚Рµ РїСѓР±Р»РёРєРѕРІР°С‚СЊ РІ Google Play:

```bash
cd client
flutter build appbundle --release
```

Р¤Р°Р№Р» Р±СѓРґРµС‚ СЃРѕР·РґР°РЅ РІ:
```
client/build/app/outputs/bundle/release/app-release.aab
```

---

## РќР°СЃС‚СЂРѕР№РєР° РїРµСЂРµРґ СЃР±РѕСЂРєРѕР№

### 1. РР·РјРµРЅРёС‚СЊ Application ID (РѕРїС†РёРѕРЅР°Р»СЊРЅРѕ)

РћС‚СЂРµРґР°РєС‚РёСЂСѓР№С‚Рµ `client/android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    applicationId = "com.stealth.messenger"  // в†ђ РёР·РјРµРЅРёС‚Рµ РЅР° СЃРІРѕР№
    minSdk = 21
    targetSdk = 34
    versionCode = 1
    versionName = "0.1.0"
}
```

### 2. РќР°СЃС‚СЂРѕРёС‚СЊ .env С„Р°Р№Р»

Создайте `client/.env` с настройками PocketBase/TURN:

```env
POCKETBASE_URL=https://signal.example.com
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your-username
TURN_PASSWORD=your-password
TURNS_URL=turns:your-turn-server.com:443?transport=tcp
TURNS_USERNAME=your-username
TURNS_PASSWORD=your-password
```

### 3. РџРѕРґРїРёСЃР°С‚СЊ APK (РґР»СЏ production)

Р”Р»СЏ production-СЃР±РѕСЂРєРё РЅСѓР¶РЅРѕ СЃРѕР·РґР°С‚СЊ keystore:

```bash
keytool -genkey -v -keystore ~/stealth-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias stealth
```

РЎРѕР·РґР°Р№С‚Рµ `client/android/key.properties`:
```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=stealth
storeFile=/path/to/stealth-release-key.jks
```

РћР±РЅРѕРІРёС‚Рµ `client/android/app/build.gradle.kts`:
```kotlin
// Р”РѕР±Р°РІСЊС‚Рµ РїРµСЂРµРґ android {}
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

## РџСЂРѕРІРµСЂРєР° СѓСЃС‚Р°РЅРѕРІРєРё

РџРѕСЃР»Рµ СѓСЃС‚Р°РЅРѕРІРєРё:

1. РћС‚РєСЂРѕР№С‚Рµ РїСЂРёР»РѕР¶РµРЅРёРµ "Stealth" РЅР° С‚РµР»РµС„РѕРЅРµ
2. Р’РІРµРґРёС‚Рµ РЅРёРєРЅРµР№Рј
3. РќР°Р¶РјРёС‚Рµ "GET STARTED"
4. РџСЂРёР»РѕР¶РµРЅРёРµ РґРѕР»Р¶РЅРѕ Р·Р°РіСЂСѓР·РёС‚СЊСЃСЏ Рё РїРѕРєР°Р·Р°С‚СЊ РіР»Р°РІРЅС‹Р№ СЌРєСЂР°РЅ СЃ С‚Р°Р±Р°РјРё

---

## РЈСЃС‚СЂР°РЅРµРЅРёРµ РїСЂРѕР±Р»РµРј

### РћС€РёР±РєР°: "Flutter not found"
```bash
# Р”РѕР±Р°РІСЊС‚Рµ Flutter РІ PATH:
# Windows (PowerShell):
$env:Path += ";C:\path\to\flutter\bin"

# РР»Рё РґРѕР±Р°РІСЊС‚Рµ РїРѕСЃС‚РѕСЏРЅРЅРѕ С‡РµСЂРµР· РЎРёСЃС‚РµРјРЅС‹Рµ РїРµСЂРµРјРµРЅРЅС‹Рµ
```

### РћС€РёР±РєР°: "Android SDK not found"
```bash
# РЈСЃС‚Р°РЅРѕРІРёС‚Рµ Android SDK С‡РµСЂРµР· Android Studio
# РР»Рё СѓСЃС‚Р°РЅРѕРІРёС‚Рµ command-line tools:
# https://developer.android.com/studio#command-tools
```

### РћС€РёР±РєР°: "device not found"
```bash
# РџСЂРѕРІРµСЂСЊС‚Рµ USB-РѕС‚Р»Р°РґРєСѓ:
adb devices

# Р•СЃР»Рё "unauthorized" вЂ” СЂР°Р·СЂРµС€РёС‚Рµ РѕС‚Р»Р°РґРєСѓ РЅР° С‚РµР»РµС„РѕРЅРµ
# Р•СЃР»Рё РЅРµ РІРёРґРёС‚ вЂ” РїРµСЂРµРїРѕРґРєР»СЋС‡РёС‚Рµ USB, РїРѕРїСЂРѕР±СѓР№С‚Рµ РґСЂСѓРіРѕР№ РєР°Р±РµР»СЊ
```

### РћС€РёР±РєР° РїСЂРё СЃР±РѕСЂРєРµ: "Execution failed for task ':app:lintVitalAnalyzeRelease'"
```bash
# РћС‚РєР»СЋС‡РёС‚Рµ lint РїСЂРѕРІРµСЂРєРё (РІСЂРµРјРµРЅРЅРѕ):
# Р’ android/app/build.gradle.kts РґРѕР±Р°РІСЊС‚Рµ:
android {
    lintOptions {
        checkReleaseBuilds = false
        abortOnError = false
    }
}
```

### РџСЂРёР»РѕР¶РµРЅРёРµ РєСЂР°С€РёС‚СЃСЏ РїСЂРё Р·Р°РїСѓСЃРєРµ
```bash
# РџСЂРѕРІРµСЂСЊС‚Рµ Р»РѕРіРё:
adb logcat | grep -i flutter

# РЈР±РµРґРёС‚РµСЃСЊ С‡С‚Рѕ .env С„Р°Р№Р» РїСЂРёСЃСѓС‚СЃС‚РІСѓРµС‚ Рё СЃРѕРґРµСЂР¶РёС‚ РєРѕСЂСЂРµРєС‚РЅС‹Рµ РґР°РЅРЅС‹Рµ
```

---

## Р Р°Р·РјРµСЂ APK

- **Debug APK:** ~80-100 MB
- **Release APK:** ~50-70 MB
- **Release APK (split-per-abi):** ~20-30 MB РЅР° Р°СЂС…РёС‚РµРєС‚СѓСЂСѓ

Р”Р»СЏ СѓРјРµРЅСЊС€РµРЅРёСЏ СЂР°Р·РјРµСЂР° РёСЃРїРѕР»СЊР·СѓР№С‚Рµ split APKs:
```bash
flutter build apk --release --split-per-abi
```

Р­С‚Рѕ СЃРѕР·РґР°СЃС‚ РѕС‚РґРµР»СЊРЅС‹Рµ APK РґР»СЏ:
- `app-armeabi-v7a-release.apk` (32-bit ARM)
- `app-arm64-v8a-release.apk` (64-bit ARM)
- `app-x86_64-release.apk` (64-bit x86)

РЈСЃС‚Р°РЅРѕРІРёС‚Рµ С‚РѕС‚, РєРѕС‚РѕСЂС‹Р№ РїРѕРґС…РѕРґРёС‚ РґР»СЏ РІР°С€РµРіРѕ С‚РµР»РµС„РѕРЅР° (РѕР±С‹С‡РЅРѕ arm64-v8a).

---

## Р‘С‹СЃС‚СЂР°СЏ РєРѕРјР°РЅРґР° (РІСЃС‘ РІ РѕРґРЅРѕРј)

```bash
# 1. РџРµСЂРµР№С‚Рё РІ РїР°РїРєСѓ РїСЂРѕРµРєС‚Р°
cd client

# 2. РџСЂРѕРІРµСЂРёС‚СЊ СѓСЃС‚СЂРѕР№СЃС‚РІР°
flutter devices

# 3. РЎРѕР±СЂР°С‚СЊ Рё СѓСЃС‚Р°РЅРѕРІРёС‚СЊ РЅР° РїРѕРґРєР»СЋС‡РµРЅРЅС‹Р№ С‚РµР»РµС„РѕРЅ
flutter run --release

# РР»Рё СЃРѕР±СЂР°С‚СЊ APK
flutter build apk --release --split-per-abi

# РЈСЃС‚Р°РЅРѕРІРёС‚СЊ РєРѕРЅРєСЂРµС‚РЅС‹Р№ APK
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

**Р“РѕС‚РѕРІРѕ!** РџСЂРёР»РѕР¶РµРЅРёРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅРѕ РЅР° С‚РµР»РµС„РѕРЅ. РўРµРїРµСЂСЊ РјРѕР¶РЅРѕ РїСЂРѕС‚РµСЃС‚РёСЂРѕРІР°С‚СЊ СЂРµР°Р»СЊРЅС‹Рµ Р·РІРѕРЅРєРё, РїРµСЂРµРґР°С‡Сѓ С„Р°Р№Р»РѕРІ Рё РёР·РѕР±СЂР°Р¶РµРЅРёР№ РЅР° СЂРµР°Р»СЊРЅРѕРј СѓСЃС‚СЂРѕР№СЃС‚РІРµ.
