# Деплой signaling-инфраструктуры на VPS

Stealth Messenger хранит данные на устройстве. На сервер выносится только:

- **PocketBase** — WebRTC signaling (`offer` / `answer` / `candidate` / `hangup`)
- **Caddy** — HTTPS для PocketBase
- **coturn** — TURN/TURNS для обхода NAT

Готовые конфиги и скрипты: [`server/docker/`](../server/docker/).

> **Версия PocketBase:** Docker-образ зафиксирован на `0.22.21` — проверенная
> совместимость с Dart SDK `pocketbase ^0.18` и realtime SSE. Для PocketBase
> 0.23+ используйте [`rtc_signaling_import_023.json`](../server/pocketbase/rtc_signaling_import_023.json)
> и обновите hook `push_dispatcher.pb.js` (см. комментарий в файле).

## Быстрый старт (SSH на VPS)

### 1. Bootstrap сервера

```bash
cd server/docker
chmod +x scripts/*.sh
./scripts/bootstrap-vps.sh
newgrp docker   # или перелогиниться
```

### 2. DNS

Создайте A-записи у регистратора:

| Имя | Тип | Значение |
|-----|-----|----------|
| `signal.your.tld` | A | публичный IP VPS |
| `turn.your.tld` | A | тот же IP |

Проверка (на VPS или локально с заполненным `.env`):

```bash
cp .env.example .env   # отредактировать
./scripts/check-dns.sh
```

### 3. Установка стека

```bash
cp .env.example .env
nano .env
./scripts/install.sh
```

Скрипт создаёт `~/stealth-server`, копирует hooks из [`server/pb_hooks/`](../server/pb_hooks/), рендерит `Caddyfile` и `coturn/turnserver.conf`, поднимает `docker compose`.

### 4. PocketBase (один раз)

```bash
./scripts/pocketbase-setup-notes.sh
```

Кратко:

1. `https://signal.your.tld/_/` — создать admin
2. Импорт `rtc_signaling` (CLI после создания admin):

   ```bash
   POCKETBASE_URL=https://signal.your.tld \
     POCKETBASE_ADMIN_EMAIL=... POCKETBASE_ADMIN_PASSWORD=... \
     ./scripts/import-rtc-signaling.sh
   ```

   Или вручную: Settings → Import collections → [`rtc_signaling_import.json`](../server/pocketbase/rtc_signaling_import.json)
3. `docker compose -f ~/stealth-server/docker-compose.yml restart pocketbase`

Подробности схемы: [`POCKETBASE_SETUP.md`](POCKETBASE_SETUP.md).

### 5. TLS для TURNS (coturn)

```bash
./scripts/issue-turn-certs.sh
```

Временно останавливает Caddy, выпускает cert через certbot, копирует в `~/stealth-server/coturn/certs/`, перезапускает стек.

### 6. Сборка Android-клиента

На машине с Flutter (можно WSL):

```bash
cd server/docker
./scripts/build-client-apk.sh
```

APK: `client/build/app/outputs/flutter-apk/app-release.apk`

Установка: [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md).

### 7. Проверка

```bash
export POCKETBASE_TEST_ADMIN_EMAIL=...
export POCKETBASE_TEST_ADMIN_PASSWORD=...
./scripts/verify-signaling.sh
```

Ручной тест звонка на двух телефонах: [`MANUAL_CALL_TEST.md`](MANUAL_CALL_TEST.md).

## Локальный smoke-тест (без домена)

```bash
cd server/docker
docker compose -f docker-compose.local.yml up -d
# Admin UI: http://127.0.0.1:8090/_/
# Импорт rtc_signaling_import.json вручную
export POCKETBASE_TEST_URL=http://127.0.0.1:8090
cd ../../client && flutter test test/services/signaling/pocketbase_signaling_smoke_test.dart
```

## Порты (UFW + панель хостера)

| Порт | Назначение |
|------|------------|
| 22/tcp | SSH |
| 80, 443/tcp | Caddy (PocketBase HTTPS) |
| 3478/tcp+udp | TURN |
| 5349/tcp | TURNS |
| 49152–65535/udp | coturn relay |

## Эксплуатация

- Бэкап: `~/stealth-server/pb_data/` или PocketBase Admin → Backup
- Обновление образов: `cd ~/stealth-server && docker compose pull && docker compose up -d`
- Логи: `docker compose logs -f pocketbase`

## Связанные документы

- [`POCKETBASE_SETUP.md`](POCKETBASE_SETUP.md) — схема и rules
- [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md) — установка APK
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — роль PocketBase и TURN
