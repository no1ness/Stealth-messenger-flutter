[Back to README](../README.md) · [Архитектура →](architecture.md)

# Начало работы

## Предварительные требования

- **Flutter SDK** ≥ 3.0.0 ([установка](https://docs.flutter.dev/get-started/install))
- **Android SDK** (через Android Studio или command-line tools)
- **Git** для клонирования репозитория

Проверка окружения:

```bash
flutter doctor
```

Убедитесь, что Flutter и Android toolchain отмечены ✅.

## Установка

```bash
# 1. Клонировать репозиторий
git clone https://github.com/no1ness/Stealth-messenger-flutter.git
cd Stealth-messenger-flutter/client

# 2. Установить зависимости
flutter pub get

# 3. Запустить (debug)
flutter run
```

По умолчанию приложение использует placeholder-значения из `.env.defaults`.
Для реальных звонков укажите свой PocketBase URL:

```bash
flutter run --dart-define=POCKETBASE_URL=https://signal.your.tld
```

## Первый запуск

1. Откройте приложение — появится экран регистрации
2. Введите никнейм
3. Нажмите **GET STARTED**
4. Приложение создаст локальную идентичность (UUID + X25519 keypair)
5. Главный экран покажет вкладки: Chats, Calls, Contacts, Profile

## Сборка APK для Android

### Debug-сборка

```bash
cd client
flutter build apk --debug
```

### Release-сборка

```bash
cd client
flutter build apk --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld
```

APK создаётся в `client/build/app/outputs/flutter-apk/`.

### Установка на устройство

```bash
# Через ADB (телефон подключён по USB, отладка включена)
adb install client/build/app/outputs/flutter-apk/app-release.apk

# Или прямой запуск на подключённом устройстве
cd client && flutter run --release
```

### Split APKs (уменьшенный размер)

```bash
flutter build apk --release --split-per-abi
```

Создаёт отдельные APK:
- `app-arm64-v8a-release.apk` — 64-bit ARM (большинство современных устройств)
- `app-armeabi-v7a-release.apk` — 32-bit ARM
- `app-x86_64-release.apk` — 64-bit x86 (эмуляторы)

## Устранение проблем

| Проблема | Решение |
|----------|---------|
| `Flutter not found` | Добавьте Flutter в PATH |
| `Android SDK not found` | Установите через Android Studio |
| `device not found` | Включите USB-отладку, проверьте `adb devices` |
| Lint ошибки при release | См. [Android Release](android-release.md) — секция Lint baseline |
| Краш при запуске | Проверьте `adb logcat \| grep flutter`, убедитесь в `.env.defaults` |

## Следующие шаги

- [Настройте PocketBase](pocketbase-setup.md) для реальных звонков
- Обменяйтесь contact bundle с другим пользователем через экран Profile

## See Also

- [Архитектура](architecture.md) — как устроен проект
- [Конфигурация](configuration.md) — переменные окружения и `.env.defaults`
- [PocketBase Setup](pocketbase-setup.md) — развёртывание signaling-сервера
