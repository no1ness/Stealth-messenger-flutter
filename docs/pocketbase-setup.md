[← Конфигурация](configuration.md) · [Back to README](../README.md) · [Android Release →](android-release.md)

# PocketBase Signaling Server — Setup Guide

Stealth Messenger использует PocketBase как WebRTC signaling channel
(offer / answer / candidate / hangup). После настройки `POCKETBASE_URL`
в конфигурации звонки работают end-to-end без legacy cloud backend.

Клиенту нужно:
- Доступный PocketBase URL (HTTPS для production, HTTP для localhost)
- Коллекция `users` с email+password auth (идёт из коробки)
- Кастомная коллекция `rtc_signaling` — см. схему ниже
- Scheduled cleanup для автоматической очистки

## 1. Развёртывание

### Docker Compose

```yaml
services:
  pocketbase:
    image: ghcr.io/muchobien/pocketbase:latest
    restart: unless-stopped
    environment:
      - TZ=UTC
    volumes:
      - ./pb_data:/pb_data
    ports:
      - "127.0.0.1:8090:8090"

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    depends_on: [pocketbase]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    ports:
      - "80:80"
      - "443:443"

volumes:
  caddy_data:
  caddy_config:
```

Minimal `Caddyfile` (замените `signal.example.com` на ваш домен):

```
signal.example.com {
    reverse_proxy pocketbase:8090
}
```

После `docker compose up -d` админ-панель доступна по адресу
`https://signal.example.com/_/`.

### MikroTik containers (RouterOS 7.4+)

PocketBase — один Go-бинарник, подходит для RouterOS container runtime:
- `interface veth` с bridge на LAN
- `container envs` с `TZ=UTC`
- `container mounts` с `dst=/pb_data, src=/disk1/pb_data`
- Start order: PocketBase → Caddy

### TLS

Клиент **не** делает certificate pinning. Для production убедитесь, что
URL — HTTPS с trusted cert. Caddy с ACME достаточен.

## 2. Схема `rtc_signaling`

Создайте base-коллекцию в admin UI или импортируйте JSON:

| Field | Type | Required | Описание |
|-------|------|:--------:|----------|
| `roomId` | text | ✅ | indexed; chatId для 1-to-1 звонков |
| `creator` | text | ✅ | PB record id отправителя (15-char SHA-256 prefix UUID) |
| `target` | text | ✅ | indexed; PB record id получателя |
| `type` | select | ✅ | `offer`, `answer`, `candidate`, `hangup` |
| `payload` | json | ✅ | SDP / candidate object; для `offer`/`hangup` — также `creatorUuid` |

Индексы:

```sql
CREATE INDEX idx_rtc_signaling_target_created
  ON rtc_signaling (target, created);
CREATE INDEX idx_rtc_signaling_room
  ON rtc_signaling (roomId);
```

## 3. API rules

| Правило | Выражение |
|---------|-----------|
| List / View | `target = @request.auth.id \|\| creator = @request.auth.id` |
| Create | `@request.auth.id != "" && @request.data.creator = @request.auth.id` |
| Update | `null` |
| Delete | `creator = @request.auth.id` |

Поле `creator` содержит PocketBase user id — 15 символов, алфавит
`^[A-Za-z0-9_]{15}$`. Клиент генерирует его как первые 15 hex-символов
`SHA-256(localUuid)` (см. `client/lib/services/signaling/pb_user_id.dart`).

Регистрация происходит в `PocketBaseAuthService.ensureAuth` (singleton,
общий для `WebRtcSignalingService` и `IncomingCallSignalingService`).

> **Обновление со старой версии.** Релизы до 2026-05-16 использовали
> UUID без дашей (32 char) — PocketBase отклонял такой id. При обновлении
> клиент обнаруживает несовпадение, сбрасывает credentials и регистрируется
> заново под корректным 15-char id.

## 4. Users collection

PocketBase поставляется с `users` auth collection. Клиент использует
email+password auth с синтетическими credentials вида
`<pbId>@stealth.local`. Разрешите публичную регистрацию (default).

## 5. Scheduled cleanup (TTL)

Создайте `pb_hooks/rtc_cleanup.pb.js`:

```js
cronAdd("rtc_cleanup", "*/10 * * * *", () => {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  $app.dao().db()
    .newQuery("DELETE FROM rtc_signaling WHERE created < {:cutoff}")
    .bind({ cutoff })
    .execute();
});
```

Перезагрузите hooks: `docker compose restart pocketbase`.

## 6. Проверка

```bash
export POCKETBASE_TEST_URL=https://signal.example.com
cd client
flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart
```

Успешный тест подтверждает: сервер доступен, схема корректна, SSE работает.

## 7. Эксплуатация

- **Бэкапы:** `pb_data/data.db` (SQLite) — backup из admin UI или filesystem
- **Мониторинг:** access logs, клиент тегирует ошибки `[signaling]`
- **TURNS:** настраивается отдельно (coturn за Caddy на 443)
- **Масштабирование:** один инстанс обслуживает тысячи SSE-клиентов

## See Also

- [Конфигурация](configuration.md) — переменные `POCKETBASE_URL`, `TURN_*`
- [Безопасность](security.md) — серверная видимость и threat model
- [Тестирование](testing.md) — signaling smoke-тест
