[← Android Release](android-release.md) · [Back to README](../README.md)

# Тестирование

## CI Quality Gates

[CI workflow](../.github/workflows/ci.yml) запускается на каждый push и PR:

| Job | Что делает |
|-----|-----------|
| `analyze + test` | `flutter pub get`, `flutter analyze`, `flutter test` |
| `build web` | `flutter build web --release` |
| `build android` | `flutter build apk --debug` (JDK 17) |
| `signaling smoke` | E2E smoke-тест PocketBase (опциональный секрет) |

Signaling smoke-тест запускается только при наличии секрета
`POCKETBASE_TEST_URL`; без него job завершается с `notice` и остаётся зелёным.

## Запуск тестов локально

```bash
cd client

# Статический анализ
flutter analyze

# Все unit/widget тесты
flutter test

# Конкретный тест
flutter test test/security/private_key_no_export_test.dart
```

## Signaling Smoke-тест

Проверяет реальное соединение с PocketBase:

```bash
cd client
export POCKETBASE_TEST_URL=https://signal.your.tld
flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart
```

Тест создаёт двух синтетических пользователей и обменивается
`offer → answer → hangup`. Если указаны `POCKETBASE_TEST_ADMIN_EMAIL` и
`POCKETBASE_TEST_ADMIN_PASSWORD`, тестовые аккаунты будут удалены по завершении.

Успешный запуск подтверждает:
1. Сервер доступен с хоста
2. Схема и правила `rtc_signaling` корректны
3. Realtime SSE доставляет события в течение ~10 секунд

## Ручное тестирование звонков

### Между телефоном и эмулятором

1. Запустите эмулятор: `emulator -avd <имя_AVD>`
2. Запустите приложение: `cd client && flutter run -d emulator-5554`
3. На телефоне: Contacts → добавьте эмулятор через contact bundle
4. На эмуляторе: Contacts → добавьте телефон через contact bundle
5. Инициируйте звонок → нажмите **Start call** → на другом устройстве **Answer**
6. Проверьте: статус «Connected», аудио передаётся

### Между двумя телефонами

1. Установите APK на оба устройства
2. Зарегистрируйте пользователей
3. Обменяйтесь contact bundle
4. Совершите звонок

### Автоматизированные Appium-тесты

```bash
# Запустите Appium-сервер
appium

# В другом терминале
cd pw-test
node appium-simple-call-test.mjs
```

Скрипты в `pw-test/`:
- `appium-call-test.mjs` — полный тест с добавлением контактов
- `appium-simple-call-test.mjs` — для уже настроенных устройств

## Чек-лист проверки звонка

- [ ] Статус соединения: «Connected»
- [ ] Аудио передаётся в обе стороны
- [ ] Видео (если включено) отображается
- [ ] Соединение стабильно, нет обрывов

## Отладка

```bash
# Логи Flutter с телефона
adb -s <device_id> logcat | grep -i flutter

# Логи с эмулятора
adb -s emulator-5554 logcat | grep -i flutter
```

## Известные ограничения

- Flutter CanvasKit рендерит UI на canvas — Appium не всегда находит элементы
- Эмулятор может отключаться при нехватке ресурсов

## See Also

- [Начало работы](getting-started.md) — установка и запуск
- [PocketBase Setup](pocketbase-setup.md) — верификация deployment
- [Безопасность](security.md) — что проверять в контексте безопасности
