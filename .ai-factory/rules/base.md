# Базовые правила проекта Stealth Messenger

> Конвенции выявлены автоматическим анализом кодовой базы. При расхождении с реальностью — отредактируй вручную.

## Соглашения по именованию

- **Файлы:** `snake_case.dart` (например, `supabase_service.dart`, `local_database_service.dart`, `p2p_discovery_service.dart`)
- **Классы / typedef'ы / enum'ы:** `PascalCase` (`MyApp`, `SupabaseService`, `ThemeMode`)
- **Переменные и поля:** `camelCase` (`themeMode`, `supabaseUrl`)
- **Приватные члены и методы:** ведущий `_` (`_isUserRegistered`, `_loadTheme`, `_initializeSupabase`)
- **Константы:** `lowerCamelCase` для `const`/`final` локальных, `kPrefix` или `SCREAMING_SNAKE_CASE` — НЕ использовать (Dart стиль)
- **Пакеты в импортах:** `package:stealth/<path>` (см. `pubspec.yaml: name: stealth`)

## Структура модулей

- `client/` — корень Flutter-приложения
- `client/lib/` — сервисы доменного слоя (один файл — один сервис: `supabase_service.dart`, `sync_service.dart`, `p2p_service.dart`, `local_database_service.dart` и т.д.)
- `client/lib/ui/screens/` — экраны (18 шт., каждый в своём файле)
- `client/lib/ui/widgets/` — переиспользуемые виджеты
- `client/lib/themes/apple_liquid/` — Apple Liquid theme: `liquid_theme.dart` + `widgets/` (glassmorphism)
- `client/supabase/migrations/` — SQL-миграции Supabase (порядковые имена с датой и описанием)
- `client/lib/storage_service_io.dart` / `storage_service_web.dart` / `storage_service_stub.dart` — платформенные реализации с conditional imports
- `pw-test/` — Node.js E2E-тесты (Playwright + Appium / WebDriverIO)
- `docs/` — техническая документация
- `.ai-factory/` — артефакты AI Factory (план, описание, правила)

## Обработка ошибок

- `try` / `catch (error)` с явной типизацией где нужно (`PlatformException`, `Exception`).
- Recovery-флоу для известных corrupted-state сценариев: однократный сброс + retry с флагом `afterReset` (см. `main.dart: _initializeSupabase(afterReset: true)`).
- UI-ошибки во время startup отображаются на отдельном экране (`startup_error_screen.dart`) с описанием и кнопкой повторной попытки.
- Перед `setState` обязательно проверять `if (!mounted) return;` после `await`.
- Бросать `Exception('...')` с понятным сообщением для критических багов окружения (например, отсутствие env переменных).

## Логирование

- Используется `debugPrint(...)` (Flutter built-in) — НЕ `print`.
- Уровень DEBUG / verbose активен по умолчанию в dev-сборке.
- Чувствительные данные (приватные ключи, plaintext сообщений, токены) в логи не пишутся.
- Логирование ошибок: `debugPrint('Error doing X: $error')`.

## Асинхронность

- `async` / `await` повсеместно. Возвращать `Future<void>` / `Future<T>`, не использовать `then()`-цепочки.
- `void main() async { ... }` для bootstrap.
- `await WidgetsFlutterBinding.ensureInitialized()` перед любым Flutter-вызовом до `runApp`.

## Состояние и UI

- `StatefulWidget` + `setState` для локального state (см. `MyApp`).
- Глобальные сервисы — синглтоны через статическое поле `instance` (например, `SyncService.instance.start()`).
- Перед обновлением state после `await` — `if (!mounted) return;`.
- Темизация через `ThemeMode` + `SharedPreferences` (`themeMode` ключ).

## Тестирование

- `dev_dependencies` включают `flutter_test`, но **на текущей фазе тесты пропускаются** (см. `.ai-factory/PLAN.md`: `Testing: Нет (skip tests)`).
- E2E — отдельная подпапка `pw-test/` (Node.js, не Dart): `appium-simple-call-test.mjs` и др.
- При добавлении тестов — следовать паттерну `*_test.dart` рядом с тестируемым файлом или в `client/test/`.

## Конфиг и секреты

- `client/.env` (флаги Supabase URL / anon key) загружается через `flutter_dotenv` в `main.dart`.
- `.env` указан в `pubspec.yaml: assets:` — НО он также должен быть в `.gitignore` (никаких реальных credentials в репозитории).
- Пользовательские настройки (toggle Supabase, custom URL, тема) — `SharedPreferences`.
- Приватные ключи — `flutter_secure_storage_x` (Android Keystore).

## Коммиты

- Conventional Commits на русском или английском (см. `PLAN.md`):
  - `fix: восстановление работоспособности WebRTC звонков и файлов`
  - `feat: внедрение RTCDataChannel для прямого обмена сообщениями`
- Один коммит — одна логически завершённая задача из `PLAN.md`.

## Платформенные особенности

- **Android — first-class.** Сборка через `flutter build apk --release --split-per-abi`.
- **Web — second-class.** Используются conditional imports (`storage_service_web.dart` и т.д.).
- **iOS — отключён.** `flutter_native_splash` и `flutter_launcher_icons` сконфигурированы только под Android.
- При добавлении нового сервиса с платформенной зависимостью — следовать паттерну `*_io.dart` / `*_web.dart` / `*_stub.dart`.
