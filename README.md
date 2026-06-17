# Stealth Messenger

[![CI](https://github.com/no1ness/Stealth-messenger-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/no1ness/Stealth-messenger-flutter/actions/workflows/ci.yml)

Local-first Flutter-мессенджер с E2E-шифрованием чатов, вложений и
WebRTC peer-to-peer звонками. PocketBase используется исключительно как
transient signaling relay для `offer / answer / candidate / hangup` —
история сообщений, контакты и вложения никогда не покидают устройство.

## Документация

| Guide | Description |
|-------|-------------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Обзор системы |
| [`docs/design-system.md`](docs/design-system.md) | Дизайн-система, токены и UI-компоненты |
| [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) | Оптимизация производительности |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Модель угроз и криптография |
| [`docs/POCKETBASE_SETUP.md`](docs/POCKETBASE_SETUP.md) | Развёртывание signaling-сервера |
| [`docs/BYPASS_SETUP.md`](docs/BYPASS_SETUP.md) | Bypass-прокси для обхода NAT |
| [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md) | Сборка под Android |
| [`docs/ANDROID_RELEASE.md`](docs/ANDROID_RELEASE.md) | Подпись release-сборки и lint |
| [`docs/deployment.md`](docs/deployment.md) | Деплой и CI/CD |
| [`AGENTS.md`](AGENTS.md) | Базовые правила для AI-ассистентов |

## Quality gates

[`CI workflow`](.github/workflows/ci.yml) запускается на каждый push и
pull request, гейтит merge'и на:

| Job                | Что делает                                           |
| ------------------ | ---------------------------------------------------- |
| `analyze + test`   | `flutter pub get`, `flutter analyze`, `flutter test` |
| `pw-test lint`     | `node pw-test/lint-contact-bundle.mjs` — гарантия что E2E-скрипты используют contact bundle |
| `build web`        | `flutter build web --release`                        |
| `build android`    | `flutter build apk --debug` (JDK 17)                 |
| `signaling smoke`  | End-to-end PocketBase smoke-тест (опциональный секрет) |

Опциональный signaling smoke-тест запускается только если настроен
секрет репозитория `POCKETBASE_TEST_URL`; без него job выходит с
аннотацией `notice` и остаётся зелёным.

Nightly + manual:

| Job                       | Когда                                                |
| ------------------------- | ---------------------------------------------------- |
| `build-android-release`   | 03:00 UTC + `workflow_dispatch`. Подписанные APK и AAB (артефакт хранится 14 дней). Требует секрет `ANDROID_KEYSTORE_BASE64` — без него job пропускается с `notice`. |
| `analyze-macos`           | 04:00 UTC + `workflow_dispatch`. Прогоняет `flutter analyze` + `flutter test` на `macos-latest`. Не в PR-матрице, чтобы не замедлять обычные PR. |

## Структура проекта

- `client/` — исходники Flutter-приложения и тесты
- `docs/` — подробная документация
- `pw-test/` — Appium / WebRTC интеграционные скрипты
- `.ai-factory/` — внутренние артефакты планирования / правил / патчей
