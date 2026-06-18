# Интеграция Sing-box (VLESS-Reality) — обход блокировок под маскировкой Яндекс.Телемоста

**Branch:** `feature/sing-box-vless-bypass`
**Created:** 2026-06-16

## Settings

| Параметр | Значение |
|---|---|
| Testing | Включить тесты |
| Logging | Verbose (DEBUG) |
| Docs | Да — обязательный чекпоинт документации |
| Roadmap linkage | M17 — Sing-box/обход блокировок |

## Roadmap Linkage

- **Milestone:** M17 — Sing-box/обход блокировок
- **Rationale:** Новая функциональность интеграции Sing-box (VLESS-Reality) под маскировкой Яндекс.Телемоста для обхода ТСПУ в РФ

## Архитектура решения

```
[Режим: Обход ВКЛ]
App -> BypassManager (Sing-box in-app: SOCKS5 :10808 + HTTP :10809)
    -> [ТСПУ: видит Яндекс.Телемост] -> Сервер Sing-box :443 (Reality)
    -> Caddy :8443 (PocketBase API)

[Режим: Обход ВЫКЛ]
App -> Напрямую -> Caddy (на альтернативном порту, т.к. Sing-box владеет портом 443)
```

**Влияние на веб-приложение:** Sing-box занимает порт 443. Веб-приложение (`app.stealthpro.ru`) и дашборд (`dashboard.*`) теряют порт 443 → временно обслуживаются на альтернативных портах (`:8445`, `:8446`) или переносятся на отдельный хостинг/CDN.

## Сетевые клиенты под прокси

### HTTP CONNECT (не SOCKS5)

Dart `HttpClient.findProxy` поддерживает **только `PROXY` (HTTP CONNECT)**, SOCKS5 НЕ поддерживается. Решение: **два входа** в клиентском конфиге Sing-box — SOCKS5 для внешних нужд и HTTP для Dart:

```json
"inbounds": [
  {"type": "socks", "tag": "socks-in", "listen": "127.0.0.1", "listen_port": 10808},
  {"type": "http",  "tag": "http-in",  "listen": "127.0.0.1", "listen_port": 10809}
]
```

PocketBase SDK (`^0.24.0`) принимает `httpClientFactory`. Прокси через HTTP CONNECT:

```dart
httpClientFactory: () => IOClient(
  HttpClient()..findProxy = (uri) => 'PROXY 127.0.0.1:10809',
)
```

### Серверная маршрутизация (без loop)

Без `override_address` трафик пойдёт `direct` к `signal.stealthpro.ru:443` → loop в Sing-box. **Решение:** `override_address: "127.0.0.1"`, `override_port: 8443` в server outbound.

### Android интеграция Sing-box (два подхода)

| | Approach A (libbox.aar) | Approach B (бинарный) |
|---|---|---|
| **Что используется** | `gomobile bind` → `libbox.aar` | CLI бинарник с релизов |
| **API** | `CommandServer` + `PlatformInterface` (380 строк Kotlin) | `Process.start()` + stdin/stdout/HTTP |
| **TUN/VPN** | Встроенная поддержка | Нужен отдельный VpnService |
| **Сложность** | Высокая (сборка Go, PlatformInterface) | Средняя (управление процессом) |
| **Надёжность** | Высокая (формальный API) | Средняя (kill/restart) |

**Приоритет:** Approach A (libbox.aar). Если сборка libbox окажется неподъёмной → fallback на Approach B.

---

## Tasks

### Phase 0: Серверная настройка (СПб)

#### Task 1 — Обновить Caddyfile + deploy-скрипты

Caddy теряет порт 443 (занят Sing-box). API на `:8443`, веб-приложение на `:8445`, дашборд на `:8446`.

**Файлы для изменения:**

| Файл | Изменение |
|---|---|
| `server/docker/Caddyfile.template` | Добавить `:8443 { reverse_proxy pocketbase:8090 }`. Удалить `SIGNAL_DOMAIN` блок |
| `server/docker/docker-compose.yml` | **Удалить `443:443`** из Caddy ports (занят Sing-box). Оставить `80:80` для ACME. Добавить `8443:8443` |
| `server/docker/scripts/install.sh` | Убрать `:443` из Caddy; Sing-box через Docker image |
| `server/docker/scripts/deploy-native.sh` | Caddy на `:8443` (PocketBase), `:8445` (web), `:8446` (dashboard) |
| `server/docker/scripts/deploy-web.sh` | Web на `:8445` (`app.stealthpro.ru:8445`) |
| `server/docker/scripts/deploy-dashboard.sh` | Dashboard на `:8446` |

**Note:** Deploy-скрипты должны читать порты из env-переменных `${WEB_FALLBACK_PORT}` и `${DASHBOARD_FALLBACK_PORT}`, а не хардкодить `:8445`/`:8446`. Это гарантирует, что переменные из `.env` не будут мёртвым грузом.

**Логирование:**
- `INFO [caddy] API on :8443, web on ${WEB_FALLBACK_PORT}, dashboard on ${DASHBOARD_FALLBACK_PORT}`
- `INFO [caddy] port 443 released to sing-box`

#### Task E — Установить Sing-box на сервер (Docker + native)

**Docker путь (`install.sh`):** Используется образ `ghcr.io/sagernet/sing-box:latest`. Никакого бинарника — сервис добавляется в `docker-compose.yml`. Sing-box не нужно устанавливать отдельно.

**Native путь (`deploy-native.sh`):** Установить бинарник + systemd unit.

**Добавить в `deploy-native.sh`:**
```bash
SING_BOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
wget -qO /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-amd64.tar.gz"
tar -xzf /tmp/sing-box.tar.gz -C /tmp/
cp "/tmp/sing-box-${SING_BOX_VERSION}-linux-amd64/sing-box" /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box
```

**Systemd unit:**
```systemd
[Unit]
Description=Sing-box VLESS-Reality
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
```

**Логирование:**
- `INFO [install] sing-box v<SING_BOX_VERSION> installed (native)` / `(docker image)`

#### Task 2 — Сгенерировать ключи VLESS-Reality

**Файл:** `server/docker/scripts/generate-vless-keys.sh`

**Важно:** Скрипт должен работать как при наличии sing-box CLI на хосте, так и в Docker-окружении (где sing-box — только контейнер). Добавить fallback на `docker run`.

```bash
#!/bin/bash
set -euo pipefail
SG() {
  if command -v sing-box &>/dev/null; then
    sing-box "$@"
  else
    docker run --rm ghcr.io/sagernet/sing-box:latest "$@"
  fi
}
echo "=== Private/Public Key Pair ==="
SG generate reality-keypair
echo ""
echo "=== Short ID (8 hex) ==="
SG generate rand --hex 8
```

#### Task 3 — Конфигурация серверного Sing-box + маршрутизация

**Файлы:** `server/docker/sing-box/config.json`, `docker-compose.yml`

**Server config (предотвращение loop):**
```json
{
  "log": { "level": "info" },
  "inbounds": [{
    "type": "vless", "tag": "vless-in",
    "listen": "::", "listen_port": 443,
    "users": [{ "uuid": "${VLESS_UUID}", "flow": "xtls-rprx-vision" }],
    "tls": {
      "enabled": true, "server_name": "telemost.yandex.ru",
      "reality": {
        "enabled": true,
        "handshake": { "server": "telemost.yandex.ru", "server_port": 443 },
        "private_key": "${VLESS_PRIVATE_KEY}",
        "short_id": ["${VLESS_SHORT_ID}"]
      }
    },
    "multiplex": { "enabled": true }
  }],
  "outbounds": [{
    "type": "direct", "tag": "caddy-out",
    "override_address": "127.0.0.1", "override_port": 8443
  }],
  "route": {
    "rules": [{ "inbound": ["vless-in"], "outbound": "caddy-out" }]
  }
}
```

**docker-compose.yml:**
```yaml
sing-box:
  image: ghcr.io/sagernet/sing-box:latest
  restart: unless-stopped
  network_mode: host
  volumes:
    - ./sing-box/config.json:/etc/sing-box/config.json:ro
  environment:
    - VLESS_UUID=${VLESS_UUID}
    - VLESS_PRIVATE_KEY=${VLESS_PRIVATE_KEY}
    - VLESS_SHORT_ID=${VLESS_SHORT_ID}
  depends_on: [caddy]
```

**Важно — env var substitution в config.json:** Docker НЕ раскрывает `${VLESS_UUID}` в файлах, смонтированных через `volumes:`. Sing-box получит буквальную строку `${VLESS_UUID}`. Решение: добавить entrypoint-обёртку в образ или volume.

**Вариант A (entrypoint, `sed`):** В Alpine `envsubst` (из `gettext`) не установлен по умолчанию. Используем `sed`:

```bash
#!/bin/sh
# sed delimiter | avoids conflict with base64 (/) in VLESS_PRIVATE_KEY
sed -e "s|\${VLESS_UUID}|$VLESS_UUID|g" \
    -e "s|\${VLESS_PRIVATE_KEY}|$VLESS_PRIVATE_KEY|g" \
    -e "s|\${VLESS_SHORT_ID}|$VLESS_SHORT_ID|g" \
    /etc/sing-box/config.template.json > /etc/sing-box/config.json
exec sing-box run -c /etc/sing-box/config.json
```

**Файлы (в `server/docker/sing-box/`):**
- `config.template.json` (тот же контент, что и `config.json`, с `${VLESS_*}` плейсхолдерами)
- `entrypoint.sh` (скрипт выше с `chmod +x`)

**docker-compose.yml:** переименовать `config.json` → `config.template.json`; добавить `entrypoint.sh` как volume:
```yaml
volumes:
  - ./sing-box/config.template.json:/etc/sing-box/config.template.json:ro
  - ./sing-box/entrypoint.sh:/etc/sing-box/entrypoint.sh:ro
entrypoint: ["/etc/sing-box/entrypoint.sh"]
```

**Логирование:**
- `INFO [sing-box] inbound vless-in on :443, routing -> caddy-out (127.0.0.1:8443)`

#### Task C — Обновить server `.env.example` и `.env`

**Файлы:** `server/docker/.env.example`, `server/docker/.env`

**Добавить:**
```
VLESS_UUID=change-me-to-a-uuid
VLESS_PRIVATE_KEY=change-me-to-private-key
VLESS_SHORT_ID=change-me-to-8-hex-chars
WEB_FALLBACK_PORT=8445
DASHBOARD_FALLBACK_PORT=8446
```

---

### Phase 1: Android — интеграция Sing-box

#### Task 4 — Собрать libbox.aar из исходников Sing-box

**Важно:** Pre-built `.aar` не существует. Необходимо собрать из репозитория `SagerNet/sing-box` с помощью `gomobile bind`.

**Требования:** Go, Android NDK (через Flutter SDK), `github.com/sagernet/gomobile`

**Шаги:**
```bash
git clone https://github.com/SagerNet/sing-box.git
cd sing-box
# Установка gomobile (форк SagerNet)
go install -v github.com/sagernet/gomobile/cmd/gomobile@v0.1.13
go install -v github.com/sagernet/gomobile/cmd/gobind@v0.1.13
gomobile init
# Сборка libbox.aar (Go → Java bindings)
make lib_android
# Результат: clients/android/libs/libbox.aar
```

**Перенести в проект:**
```bash
mkdir -p client/android/app/libs
cp /path/to/libbox.aar client/android/app/libs/
```

**Добавить в `build.gradle.kts`** (создать блок `dependencies { }` если отсутствует):
```kotlin
android { ... }
dependencies {
    implementation(files("libs/libbox.aar"))
}
```

**Dart `BypassManager` (Task 6) нужно реализовать до сборки libbox с заглушкой `MethodChannel`.** После получения libbox заменить заглушку на реальную реализацию. Это позволяет тестировать Dart-сторону независимо.

**Fallback (если сборка libbox невозможна):** Approach B — бинарный. Скачать `sing-box-*-android-arm64.tar.gz` с релизов, распаковать и запускать как subprocess.

**Логирование:**
- `DEBUG [native] libbox loaded, version: <version>`
- `WARN [native] libbox not available, falling back to binary mode`

#### Task 5 — Создать BypassManager (Kotlin)

**Важно:** Tasks 5, 6, и F модифицируют `MainActivity.kt` — все изменения должны быть в одном коммите (Commit 2). **Порядок реализации в Commit 2:**
1. Task 5: создать `BypassManager.kt` (чистый Kotlin, без MethodChannel)
2. Task F: добавить `VpnService.prepare()` логику в `MainActivity.kt`
3. Task 6: добавить `configureFlutterEngine` с `MethodChannel` в `MainActivity.kt` + Dart wrapper

**Файл:** `client/android/app/src/main/kotlin/com/stealth/messenger/BypassManager.kt`

**API (через MethodChannel):**
```kotlin
object BypassManager {
    const val SOCKS_PORT = 10808
    const val HTTP_PORT = 10809

    fun startBypass(context: Context, serverIp: String, uuid: String, publicKey: String, shortId: String)
    fun stopBypass()
    fun isRunning(): Boolean
}
```

**Два режима реализации:**

**Approach A (libbox):** Использовать `CommandServer` + реализовать `PlatformInterface`.
```kotlin
// Псевдокод — реальный API зависит от libbox
val commandServer = CommandServer()
val platform = PlatformInterfaceWrapper(context)  // ~380 строк
commandServer.startOrReloadService(clientConfigJson, null)
```

`PlatformInterface` включает: `openTun()`, `findConnectionOwner()`, `getInterfaces()`, `readWIFIState()`, `systemCertificates()`, `localDNSTransport()`, `startDefaultInterfaceMonitor()`.

**Approach B (бинарный):** Запустить sing-box CLI бинарник как subprocess.
```kotlin
val process = ProcessBuilder("/data/data/${context.packageName}/files/sing-box", "run", "-c", configPath)
    .directory(context.filesDir)
    .start()
// Чтение stdout для мониторинга
```

**Client config (HTTP + SOCKS):**
```json
{
  "inbounds": [
    {"type": "socks", "tag": "socks-in", "listen": "127.0.0.1", "listen_port": 10808},
    {"type": "http", "tag": "http-in", "listen": "127.0.0.1", "listen_port": 10809}
  ],
  "outbounds": [{
    "type": "vless", "tag": "vless-out",
    "server": "<SERVER_IP>", "server_port": 443,
    "uuid": "<UUID>", "flow": "xtls-rprx-vision",
    "tls": {
      "server_name": "telemost.yandex.ru",
      "reality": {
        "enabled": true, "public_key": "<PUBLIC_KEY>", "short_id": "<SHORT_ID>"
      }
    }
  }]
}
```

**Логирование:**
- `INFO [BypassManager] starting (mode: libbox/binary)`
- `INFO [BypassManager] stopped`
- `ERROR [BypassManager] start failed: <exception>`

**Тесты:**
- Unit test: isRunning() false до start, true после
- Unit test: stopBypass() → isRunning() false
- Unit test: double start idempotent

#### Task F — Android VPN permission UX

Перед запуском BypassManager (особенно в TUN-режиме) необходимо получить согласие пользователя на VPN.

**Файл:** `client/android/app/src/main/kotlin/com/stealth/messenger/MainActivity.kt`

**При первом включении обхода:**
```kotlin
val intent = VpnService.prepare(context)
if (intent != null) {
    // Показать системный диалог согласия
    startActivityForResult(intent, VPN_REQUEST_CODE)
} else {
    // Разрешение уже дано
    BypassManager.startBypass(...)
}
```

**Если пользователь отклонил VPN →** не запускать BypassManager, показать Snackbar/Toast.

**В Flutter:** `BypassStateController.enable()` возвращает `false` если VPN не разрешён.

**Логирование:**
- `INFO [vpn] permission granted`
- `WARN [vpn] permission denied — bypass not started`

#### Task 6 — Flutter MethodChannel wrapper

**Файлы:** `client/lib/services/bypass/bypass_manager.dart`, `MainActivity.kt`

**Dart API:**
```dart
class BypassManager {
  static const SOCKS_PORT = 10808;
  static const HTTP_PORT = 10809;

  static Future<void> start({required String serverIp, required String uuid, required String publicKey, required String shortId}) async { ... }
  static Future<void> stop() async { ... }
  static Future<bool> isRunning() async { ... }
}
```

**Platform channel:** `com.stealth.messenger/bypass`

**Android impl:** `MainActivity.kt` — `configureFlutterEngine` с MethodChannel, делегирующим `BypassManager`.

**Platform fallback:** web/iOS → `start()` бросает `UnsupportedError('BypassManager is Android-only')`.

**Логирование:**
- `DEBUG [bypass] channel: start(serverIp=$serverIp)`
- `DEBUG [bypass] channel: stop`

**Тесты:**
- Unit test: channel invocations decode correctly
- Widget test: start/stop не падают на mocked platform

---

### Phase 2: Env config (client)

#### Task A — Добавить BYPASS_* env ключи в `bootstrap_env.dart`

**Файл:** `client/lib/bootstrap_env.dart`

**Добавить 4 ключа в `kDartDefineEnvKeys` и case в `fromEnvironmentByKey()`.**

#### Task B — Добавить BYPASS_* env ключи в `.env.defaults`

**Файл:** `client/.env.defaults`

**Добавить:**
```
BYPASS_SERVER_IP=change_me
BYPASS_UUID=change_me
BYPASS_PUBLIC_KEY=change_me
BYPASS_SHORT_ID=change_me
```

---

### Phase 3: Сеть + координация

#### Task 8 — HTTP CONNECT прокси для PocketBase через httpClientFactory

**Файлы:** `client/lib/services/signaling/pocketbase_client.dart`, `client/pubspec.yaml`

**Добавить зависимость в `pubspec.yaml`:**
```yaml
dependencies:
  http: ^1.2.0     # IOClient для прокси (Task 8 — bypass)
```

**Добавить импорты в `pocketbase_client.dart`:****
```dart
import 'dart:io';                                    // HttpClient
import 'package:http/io_client.dart';                 // IOClient
import 'package:flutter/foundation.dart' show kIsWeb; // Web guard
```

**Добавить `reconfigure()` с прокси-фабрикой и платформенным ветвлением:**
```dart
static void reconfigure({String? proxyHost, int proxyPort = 10809}) {
  // Web: dart:io недоступен
  if (kIsWeb) {
    Logger.warn('proxy not supported on this platform');
    return;
  }
  final url = dotenv.env['POCKETBASE_URL']?.trim();
  if (url == null || url.isEmpty) throw StateError('POCKETBASE_URL not configured');
  final old = _instance;
  http.Client Function()? httpClientFactory;
  if (proxyHost != null) {
    final host = proxyHost; final port = proxyPort;
    httpClientFactory = () => IOClient(
      HttpClient()..findProxy = (uri) => 'PROXY $host:$port'..connectionTimeout = Duration(seconds: 15),
    );
  }
  _instance = PocketBaseClient._(PocketBase(url, httpClientFactory: httpClientFactory ?? http.Client.new));
  // Старый клиент закрывается после создания нового
  try { old?.pb.close(); } catch (_) {}
}
```

**Важно:** `reconfigure()` синхронно заменяет клиент. Старый клиент закрывается после того как новый уже создан — это исключает race condition при SSE reconnect (Task G).

**Логирование:**
- `INFO [pocketbase] proxy ON via 127.0.0.1:10809`
- `INFO [pocketbase] proxy OFF`
- `WARN [pocketbase] proxy not supported on this platform`

**Тесты:**
- Unit test: `reconfigure(proxyHost: "127.0.0.1")` → прокси-фабрика
- Unit test: `reconfigure()` → `http.Client.new`

#### Task G — SSE reconnection after reconfigure (all services)

`PocketBaseClient.reconfigure()` вызывает `old?.pb.close()`, что обрывает SSE-подписки ВСЕХ сервисов, а не только `WebRtcSignalingService`. Затронуты три сервиса:

| Сервис | Файл | Поле | SSE коллекция |
|--------|------|------|---------------|
| `WebRtcSignalingService` | `webrtc_signaling_service.dart:47` | `final PocketBase _pb` | `rtc_signaling` (per-call) |
| `IncomingCallSignalingService` | `incoming_call_service.dart:85` | `final PocketBase _pb` | `rtc_signaling` (глобальный) |
| `PresenceService` | `presence_service.dart:20` | `final PocketBase _pb` | `user_profiles` |

**Решение:** Перенести событие реконнекта в `PocketBaseClient` (логический владелец). Все три сервиса подписываются на него.

**Файл 1:** `client/lib/services/signaling/pocketbase_client.dart`

**Добавить импорт:** `import 'dart:async';` (для `StreamController`)

**Добавить статический StreamController после поля `pb`:**
```dart
/// Сигнал для всех SSE-подписчиков: клиент пересоздан, обновите `_pb`.
static final onReconfigure = StreamController<void>.broadcast();
```

В конце `reconfigure()` добавить оповещение:
```dart
onReconfigure.add(null);
```

Добавить `dispose()`:
```dart
static void disposeReconfigure() {
  onReconfigure.close();
}
```

**Файл 2:** `client/lib/services/signaling/webrtc_signaling_service.dart`

Изменить `final PocketBase _pb` → `PocketBase _pb` (non-final).

Подписаться на `PocketBaseClient.onReconfigure.stream`:
```dart
static StreamSubscription<void>? _resetSub;
static void _onPocketBaseReset() { /* см. ниже */ }
// В initState или конструкторе:
_resetSub ??= PocketBaseClient.onReconfigure.listen((_) => _onPocketBaseReset());
```

При срабатывании:
1. Отписаться от текущей SSE (`_unsubscribe?.call()`)
2. Обновить `_pb = PocketBaseClient.instance.pb`
3. Переподписаться (`_subscribe()`)

Отменить `_resetSub` в `dispose()`.

**Файл 3:** `client/lib/services/signaling/incoming_call_service.dart`

Те же изменения:
- `final PocketBase _pb` → `PocketBase _pb` (non-final)
- Подписаться на `PocketBaseClient.onReconfigure`
- При срабатывании: `stop()` (отписаться от SSE), обновить `_pb`, `start()`

**Файл 4:** `client/lib/services/user_directory/presence_service.dart`

Те же изменения:
- `final PocketBase _pb` → `PocketBase _pb` (non-final)
- Подписаться на `PocketBaseClient.onReconfigure`
- При срабатывании: отписаться от SSE (`_unsubscribe?.call()`), обновить `_pb`, вызвать `_subscribe()`

**В `BypassStateController.enable()`** после `reconfigure()`: `PocketBaseClient.onReconfigure.add(null)`

**Логирование:**
- `INFO [signaling] PocketBase reset detected, re-subscribing SSE` (WebRtcSignalingService)
- `INFO [signaling] incoming-call reset detected, re-subscribing` (IncomingCallSignalingService)
- `INFO [presence] PocketBase reset detected, re-subscribing` (PresenceService)

#### Task 9 — Документировать ICE/TURN при обходе

SOCKS5/HTTP CONNECT не влияют на WebRTC (системные сокеты). Добавить doc-комментарий в `buildIceServers()`.

**Логирование:**
- `DEBUG [ice-config] bypass proxy does not affect ICE`

#### Task D — BypassStateController (координатор)

**Файл:** `client/lib/services/bypass/bypass_state_controller.dart`

```dart
class BypassStateController {
  static final instance = BypassStateController._();
  bool get isBypassActive;
  Future<bool> enable();    // true если успешно
  Future<void> disable();
  Stream<bool> get onBypassChanged;
}
```

**Логика `enable()`:**
1. Прочитать `BYPASS_*` из `.env`
2. Валидировать `!= change_me`
3. **Запросить VPN permission** (Task F) — если отклонён, вернуть `false`
4. Вызвать `BypassManager.start(...)` с параметрами
5. Вызвать `PocketBaseClient.instance.reconfigure(proxyHost: "127.0.0.1", proxyPort: 10809)`
6. **Оповестить SSE реконнект** через `WebRtcSignalingService.onPocketBaseReset`
7. Обновить `_isBypassActive`, уведомить `onBypassChanged`
8. Вернуть `true`

**Edge cases:**
- **Web/iOS:** `enable()` логирует WARN, возвращает `false`.
- **POCKETBASE_URL валидация:** URL не меняется, валидация проходит.

**Логирование:**
- `INFO [bypass] enabled (HTTP CONNECT :10809)`
- `INFO [bypass] disabled`
- `ERROR [bypass] enable failed: <details>`
- `INFO [bootstrap] bypass state restored from prefs`

**Тесты:**
- Unit test: enable/disable toggle
- Unit test: enable with `change_me` → error
- Unit test: double enable idempotent

#### Task H — Восстановление bypass state после перезапуска приложения

**Файл:** `client/lib/main.dart`

После инициализации PocketBase (после `PocketBaseClient.init()`) и до `runApp()`, добавить восстановление состояния bypass из SharedPreferences:

```dart
final bypassEnabled = await prefs.getBool('bypassEnabled') ?? false;
if (bypassEnabled) {
  await BypassStateController.instance.enable();
}
```

Важно: `enable()` должен вызываться **после** инициализации PocketBase, так как он вызывает `PocketBaseClient.instance.reconfigure()`.

**Логирование:**
- `INFO [bootstrap] bypass state restored from prefs`

**Edge case:** Если enable() упал (сервер недоступен, env невалиден), сохранить `prefs.setBool('bypassEnabled', false)` — не блокировать запуск приложения.

---

### Phase 4: UI

#### Task 7 — Тумблер "Bypass" в SettingsScreen

**Файл:** `client/lib/ui/screens/settings_screen.dart`

**Логика:**
1. `_bypassEnabled` (bool, SharedPreferences key `'bypassEnabled'`)
2. Вкл: `await BypassStateController.instance.enable()` → если false, не менять UI
3. Выкл: `await BypassStateController.instance.disable()`
4. Подписаться/отписаться от `onBypassChanged` в dispose()
5. **Diagnostics:** добавить параметр `bool Function() isBypassActive` в конструктор `DiagnosticsService`, новый `_collectBypass()` метод, интеграцию в `_collect()` (добавить в `Future.wait`)

**UI:** Switch "Bypass censorship" в карточку `Connection & Storage`, после P2P-переключателя.

**Импорт:** `import 'package:stealth/services/bypass/bypass_state_controller.dart';`

**В `_loadSettings()`** после загрузки `useP2P`:
```dart
_bypassEnabled = prefs.getBool('bypassEnabled') ?? false;
```

**Управление подпиской `onBypassChanged`:** добавить `StreamSubscription<bool>? _bypassSub;` в `_SettingsScreenState`; в `initState()` подписаться; в `dispose()` вызвать `_bypassSub?.cancel()`.

**Логирование:**
- `INFO [settings] bypass toggled: enabled/disabled`

**Тесты:**
- Widget test: toggle → BypassStateController.enable/disable
- Integration test: toggle меняет соединение

---

### Phase 5: Тестирование

#### Task 10 — Интеграционные тесты

**Файл:** `client/test/features/bypass_test.dart`

**Автоматические тесты:**
1. **Bypass OFF:** `PocketBaseClient.instance.pb` → `http.Client.new`
2. **Bypass ON (mock):** enable() → `PocketBaseClient` с прокси-фабрикой
3. **Toggle roundtrip:** enable → disable → isRunning() == false

**Manual Checklist:** (в документации)
- Server probe: IP сервера в браузере → Яндекс.Телемост
- Client probe: включить обход → логи `PROXY 127.0.0.1:10809`

---

### Phase 6: Документация

#### Task 11 — server/README.md + docs/BYPASS_SETUP.md

**Файлы:** `server/docker/README.md`, `docs/BYPASS_SETUP.md`

**Содержание:**
1. Архитектура (схема)
2. Генерация ключей
3. Настройка сервера (Docker + native пути)
4. Сборка клиента (`flutter build --dart-define=BYPASS_...`)
5. Использование тумблера
6. Влияние на веб-приложение
7. Manual Checklist
8. FAQ

---

## Commit Plan

| # | Коммит | Tasks | Сообщение |
|---|---|---|---|
| 1 | Server | T1, TE, T2, T3, TC | `feat(server): sing-box on :443, Caddy API on :8443, deploy scripts` |
| 2 | Android lib + VPN | T4, T5, TF, T6 | `feat(android): build libbox.aar, BypassManager (libbox/binary), VPN permission` |
| 3 | Config | TA, TB | `feat(flutter): BYPASS_* env keys` |
| 4 | Network | T8, TG, T9, TD, TH | `feat(flutter): proxy-aware PocketBase + SSE reconnect + BypassStateController + state restore` |
| 5 | UI | T7 | `feat(settings): bypass toggle + diagnostics` |
| 6 | Tests + docs | T10, T11 | `test: bypass tests; docs: BYPASS_SETUP.md` |

**Cross-commit dependencies:**
- Commit 4 (BypassStateController) вызывает `BypassManager.start()` из Commit 2 и читает `BYPASS_*` из Commit 3 — интеграционное тестирование возможно только после Commits 2–4.
- Commit 5 (UI toggle) зависит от BypassStateController (Commit 4).
