# PocketBase Signaling Server — гайд по развёртыванию

Этот документ описывает как развернуть PocketBase-бэкенд, который Stealth
Messenger использует как WebRTC signaling-канал (offer / answer /
candidate / hangup). Как только `POCKETBASE_URL` в `client/.env` указывает
на достижимый инстанс — звонки работают end-to-end, без какого-либо
legacy cloud backend'а.

Stealth-клиенту достаточно:

- Достижимый PocketBase URL (HTTPS рекомендуется, plain HTTP — только для
  локальной разработки).
- Коллекция `users` с email+password аутентификацией (PocketBase из коробки её даёт).
- Кастомная коллекция `rtc_signaling` — схема ниже.
- Scheduled cleanup hook, чтобы коллекция не росла бесконечно.

Signaling-слой игнорирует остальной функционал PocketBase; можно
self-host'ить бинарник на VPS, в MikroTik-контейнере на homelab'е или в
любом container runtime.

## 1. Развёртывание бинарника

### 1.1 Local / VPS через docker compose

Положи сниппет ниже в `pocketbase/docker-compose.yml` рядом с volume
`pb_data/`:

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

Минимальный `Caddyfile` (замени `signal.example.com` на свой домен):

```
signal.example.com {
    reverse_proxy pocketbase:8090
}
```

После `docker compose up -d` admin UI будет доступен по
`https://signal.example.com/_/`. Создай первого админа через промпт,
который появится в логах контейнера (`docker compose logs pocketbase`).

### 1.2 MikroTik containers (RouterOS 7.4+)

PocketBase — один Go-бинарник, поэтому он хорошо ложится в RouterOS
container runtime. Тащи тот же образ, mount'и `/disk1/pb_data` для
persistence и настрой NAT-правило, чтобы порт 443 доходил до Caddy
контейнера. Полный walkthrough — за рамками этого документа, но
ключевые проверенные настройки:

- `interface veth` с bridge на LAN bridge.
- `container envs` с `TZ=UTC`.
- `container mounts` с `dst=/pb_data, src=/disk1/pb_data`.
- Порядок старта: PocketBase → Caddy.

Если фронтишь контейнер MikroTik DNS, укажи `signal.<your-domain>` на
роутер и дай Caddy получить Let's Encrypt сертификат через HTTP-01.

### 1.3 Заметки про TLS

Stealth-клиент отказывается стартовать когда `POCKETBASE_URL` пустой
(см. `client/lib/main.dart`), но он **не** pin'ит сертификаты. Для
production убедись что URL — HTTPS, и cert доверен устройству. Caddy
с дефолтным ACME-флоу — достаточно.

## 2. Схема `rtc_signaling`

Создай коллекцию из admin UI (Collections → New collection → `base`),
либо импортируй JSON через Settings → Import collections.

| Поле       | Тип          | Required | Заметки                                                     |
| ---------- | ------------ | -------- | ----------------------------------------------------------- |
| `roomId`   | text         | yes      | indexed; равен chatId для 1-к-1 звонков                     |
| `creator`  | text         | yes      | локальный user UUID отправителя (не relation: см. §4)       |
| `target`   | text         | yes      | indexed; локальный user UUID получателя                     |
| `type`     | select       | yes      | значения: `offer`, `answer`, `candidate`, `hangup`          |
| `payload`  | json         | yes      | сырой SDP / candidate-объект, передаётся как есть           |

Рекомендуемые индексы (Settings → Indexes):

```
CREATE INDEX idx_rtc_signaling_target_created
  ON rtc_signaling (target, created);
CREATE INDEX idx_rtc_signaling_room
  ON rtc_signaling (roomId);
```

Индекс по `created` делает cleanup-запрос (§5) дешёвым; индекс по
`roomId` — для ad-hoc дебага в admin UI.

## 3. API rules

Выстави rules на коллекции `rtc_signaling` так, чтобы каждый
пользователь видел только сообщения, адресованные ему, и мог постить
только сообщения, подписанные своим identity:

- **List / View rule**

  ```
  target = @request.auth.id || creator = @request.auth.id
  ```

- **Create rule**

  ```
  @request.auth.id != "" && @request.data.creator = @request.auth.id
  ```

- **Update rule**

  ```
  null
  ```

- **Delete rule**

  ```
  creator = @request.auth.id
  ```

Эти rules предполагают что поле `creator` хранит PocketBase user id
(аутентифицированный `users.id`). Lazy auth-флоу Stealth регистрирует
per-device PocketBase аккаунт, чей id совпадает с локальным user UUID,
записанным в `creator`/`target` (см.
`client/lib/services/signaling/webrtc_signaling_service.dart`, метод
`_ensureAuth`).

Если предпочитаешь, чтобы `creator`/`target` были `relation` вместо
`text` — поменяй тип и обнови rules использовать `creator.id` /
`target.id`. Stealth-клиент обращается с полем как с opaque id в любом случае.

## 4. Коллекция `users`

PocketBase из коробки даёт auth-коллекцию `users`; ничего дополнительно
не нужно. Клиент использует `email + password` auth с синтетическими
кредами вида `<localUuid>@stealth.local`. Разреши публичную регистрацию
(дефолт) или вызывай `pb.collection('users').create()` из своих
admin-тулов — клиент логинится по паролю как только запись существует.

## 5. Scheduled cleanup (TTL)

Без cleanup'а коллекция растёт на каждое signaling-сообщение. Добавь hook
в `pb_hooks/rtc_cleanup.pb.js`, чтобы удалять записи старше 1 часа:

```js
// Запускается каждые 10 минут, держит только последний час signaling-трафика.
cronAdd("rtc_cleanup", "*/10 * * * *", () => {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  $app.dao().db()
    .newQuery("DELETE FROM rtc_signaling WHERE created < {:cutoff}")
    .bind({ cutoff })
    .execute();
});
```

Перезагрузи hooks (`docker compose restart pocketbase`) — job должен
появиться в `_/#/settings/logs`.

Если нужны более строгие гарантии (например, удаление on disconnect) —
управляй cleanup'ом с application layer: каждый peer вызывает
`pb.collection('rtc_signaling').delete(record.id)` после потребления
записи. Текущая реализация Stealth этого **не** делает; SQL TTL выше
достаточен для типичного call-трафика.

## 6. Верификация развёртывания

Из корня Stealth-клиента:

```bash
export POCKETBASE_TEST_URL=https://signal.example.com
flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart
```

Тест прогоняет offer → answer → hangup между двумя синтетическими
юзерами через реальный бэкенд. Если дополнительно экспортируешь
`POCKETBASE_TEST_ADMIN_EMAIL` и `POCKETBASE_TEST_ADMIN_PASSWORD` —
он подчистит throwaway users в конце.

Зелёный прогон подтверждает:

1. Сервер достижим с хоста, где запускается `flutter test`.
2. Схема и rules `rtc_signaling` корректны.
3. Realtime SSE доставляет in-room сообщения за ~10 секунд.

## 7. Операционные заметки

- **Бэкапы.** PocketBase хранит всё в `pb_data/data.db` (SQLite).
  Снимок volume'а — через admin UI (Settings → Backup) или средствами
  файловой системы.
- **Мониторинг.** Подключи access-логи PocketBase к своему logging-stack
  — клиент тегает signaling-ошибки `[signaling]`, кросс-референс
  прямолинейный.
- **TURNS.** PocketBase везёт только signaling. Для media нужен TURN /
  TURNS сервер; клиент ожидает `TURNS_URL`, `TURNS_USERNAME`,
  `TURNS_PASSWORD` сконфигурированы отдельно (обычно `coturn` за Caddy
  на порту 443).
- **Масштабирование.** Один инстанс PocketBase держит тысячи
  параллельных SSE-клиентов на типовом железе. Horizontal scaling
  сейчас PocketBase'ом не поддерживается; если перерос один узел —
  переноси signaling на managed pub/sub.
