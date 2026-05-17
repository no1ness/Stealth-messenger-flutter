[← Безопасность](security.md) · [Back to README](../README.md) · [PocketBase Setup →](pocketbase-setup.md)

# Конфигурация

## Механизм конфигурации

Stealth использует трёхуровневую систему настроек:

| Приоритет | Источник | Назначение |
|-----------|----------|------------|
| 1 (высший) | `--dart-define=KEY=value` | Build-time / CI |
| 2 | `client/.env` (gitignored) | Локальная разработка |
| 3 (fallback) | `client/.env.defaults` (committed) | Placeholder-значения |

`main.dart` при старте проверяет `String.fromEnvironment(...)` для каждого ключа
и перезаписывает `dotenv.env`, поэтому `--dart-define` всегда побеждает.

## Переменные окружения

| Переменная | Обязательна | По умолчанию | Описание |
|------------|:-----------:|-------------|----------|
| `POCKETBASE_URL` | ✅ | `https://signal.example.com` | URL PocketBase signaling backend |
| `TURN_URL` | — | `turn:openrelay.metered.ca:80,...` | TURN-сервер (UDP/TCP) для WebRTC relay |
| `TURN_USERNAME` | — | `openrelayproject` | Логин TURN |
| `TURN_PASSWORD` | — | `openrelayproject` | Пароль TURN |
| `TURNS_URL` | — | `turns:CHANGE_ME.example:443?transport=tcp` | TURNS-сервер (TLS на 443) |
| `TURNS_USERNAME` | — | *(пусто)* | Логин TURNS |
| `TURNS_PASSWORD` | — | *(пусто)* | Пароль TURNS |

> **Важно:** значения по умолчанию — placeholder'ы. Звонки не будут работать
> без реального `POCKETBASE_URL` и TURN/TURNS-сервера.

## Способы задания конфигурации

### 1. Build-time через `--dart-define`

Рекомендуемый способ для CI и production:

```bash
flutter run \
  --dart-define=POCKETBASE_URL=https://signal.your.tld \
  --dart-define=TURN_URL=turn:your-turn.tld:3478

flutter build apk --release \
  --dart-define=POCKETBASE_URL=https://signal.your.tld
```

### 2. Локальный `.env` файл

Для ежедневной разработки создайте `client/.env`:

```env
POCKETBASE_URL=https://signal.your.tld
TURN_URL=turn:your-turn.tld:3478
TURN_USERNAME=myuser
TURN_PASSWORD=mypass
TURNS_URL=turns:your-turn.tld:443?transport=tcp
TURNS_USERNAME=myuser
TURNS_PASSWORD=mypass
```

Файл `.env` находится в `.gitignore` и **не** входит в asset bundle.

### 3. Правка `.env.defaults`

Для удобства можно редактировать `.env.defaults` напрямую, но чтобы
не закоммитить секреты:

```bash
git update-index --skip-worktree client/.env.defaults
```

Откатить:

```bash
git update-index --no-skip-worktree client/.env.defaults
```

## Безопасность конфигурации

- `.env` в `.gitignore` — секреты не попадут в репозиторий
- `.env.defaults` содержит только placeholder-значения
- Приватные ключи пользователя хранятся в secure storage устройства, **не** в env

## See Also

- [Начало работы](getting-started.md) — установка и первый запуск
- [PocketBase Setup](pocketbase-setup.md) — развёртывание signaling-сервера
- [Безопасность](security.md) — модель безопасности и криптография
