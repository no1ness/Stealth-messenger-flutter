# Базовые правила проекта Stealth Messenger

## Архитектура

- Приложение local-first: контакты, чаты, сообщения, вложения и история звонков живут локально.
- `LocalAppService` - основной facade для UI.
- `LocalDatabaseService` - локальная зашифрованная БД.
- `P2PService` - WebRTC DataChannel messaging.
- `WebRtcSignalingService` - PocketBase signaling для offer/answer/candidate/hangup.
- PocketBase используется только как transient signaling layer, а не как history store.

## Запрещено без отдельного решения

- Добавлять внешний cloud backend для контактов или истории.
- Добавлять background sync истории на внешний сервер.
- Хранить приватные ключи, plaintext сообщений или расшифрованные вложения вне устройства.

## Конвенции

- Файлы Dart: `snake_case.dart`.
- Классы: `PascalCase`.
- Переменные и поля: `camelCase`.
- Приватные члены: ведущий `_`.
- Импорты внутри клиента: `package:stealth/<path>`.

## Структура

- `client/lib/` - сервисы доменного слоя и Flutter entrypoints.
- `client/lib/ui/screens/` - экраны.
- `client/lib/ui/widgets/` - переиспользуемые виджеты.
- `client/lib/services/signaling/` - PocketBase/WebRTC signaling.
- `docs/` - актуальная документация.
- `pw-test/` - E2E scripts.

## Ошибки и состояние

- После `await` перед `setState` проверять `mounted`.
- Для startup failures использовать `StartupErrorScreen`.
- Recovery corrupted secure storage: один wipe локальных credentials и retry.
- Логи через `debugPrint`, не через `print`.
- Не логировать приватные ключи, plaintext сообщений, пароли, tokens.

## Конфиг

- `client/.env` загружается через `flutter_dotenv`.
- Обязательный ключ: `POCKETBASE_URL`.
- TURN/TURNS задаются через `TURN_*` и `TURNS_*`.
- `.env` должен оставаться в `.gitignore`.

## Проверка

- Для Flutter changes: `flutter pub get`, `flutter analyze`, targeted `flutter test`.
- Для E2E: scripts из `pw-test/`, после обновления contact-bundle flow.
- Если Flutter/Dart недоступны в PATH, явно сообщить, что проверка не выполнена.
