Markdown
# Техническое задание для ИИ-агента: Интеграция Sing-box (VLESS-Reality) под маскировкой Яндекс.Телемоста

## 1. Архитектура системы

[Режим: Обход ВКЛ]
Клиент (App) -> Локальный прокси (Sing-box внутри App) -> [ТСПУ: видит Яндекс.Телемост] -> Сервер (Внешний порт 443: Sing-box) -> Локальный Caddy (8443) / Coturn

[Режим: Обход ВЫКЛ]
Клиент (App) -> Напрямую -> Сервер (Внешний порт 443: Caddy) / Coturn


---

## 2. Часть 1. Настройка сервера (СПб)

### Шаг 1.1. Подготовка конфигурации Caddy
Изменить `Caddyfile`, чтобы освободить порт 443 для Sing-box, но оставить возможность работать напрямую.

1. Изменить порт Caddy на внутренний (например, `8443`).
2. Отключить автоматический TLS для этого порта, так как Sing-box будет сам расшифровывать трафик Reality.

**Пример конфигурации `Caddyfile`:**
```caddy
:8443 {
    reverse_proxy /api/* localhost:8090 # PocketBase API
    reverse_proxy /_/* localhost:8090   # PocketBase Admin
}
Шаг 1.2. Генерация ключей для VLESS-Reality
Сгенерировать пару ключей (приватный и публичный) и ShortID для настройки протокола Reality.

Команда для выполнения на сервере через SSH:

Bash
sing-box generate reality-keypair
sing-box generate rand --hex 8
Шаг 1.3. Написание config.json для серверного Sing-box
Создать файл конфигурации /etc/sing-box/config.json.

Критические параметры маскировки под Телемост:

server_name (SNI): telemost.yandex.ru

dest: telemost.yandex.ru:443 (куда проксировать тех, кто зашел без ключа)

Шаблон конфига (JSON):

JSON
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "id": "ГЕНЕРИРУЕМЫЙ_UUID_ПОЛЬЗОВАТЕЛЯ",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "telemost.yandex.ru",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "telemost.yandex.ru",
            "server_port": 443
          },
          "private_key": "ПРИВАТНЫЙ_КЛЮЧ_СЕРВЕРА",
          "short_id": [
            "ГЕНЕРИРУЕМЫЙ_SHORT_ID"
          ]
        }
      },
      "multiplex": {
        "enabled": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "inbound": ["vless-in"],
        "outbound": "direct"
      }
    ]
  }
}
3. Часть 2. Модификация клиентского приложения (Android)
Использовать sing-box как встроенную библиотеку (In-App Proxy), а не как глобальный VPN-сервис телефона. Это позволит управлять обходом внутри одной кнопки в кодовой базе мессенджера.

Шаг 2.1. Подключение библиотеки Sing-box
Добавить зависимость в проект (например, в build.gradle для Android):

Скачать актуальный .aar бинарник ядра со страницы релизов SagerNet/sing-box.

Подключить его как локальный модуль.

Шаг 2.2. Создание Менеджера Обхода Блокировок (BypassManager)
Написать класс-синглтон, который будет запускать и останавливать локальный прокси-сервер на устройстве.

Логика работы класса (Псевдокод для Kotlin/Java):

Kotlin
object BypassManager {
    private var boxInstance: Box? = null
    const val LOCAL_PROXY_PORT = 10808

    fun startBypass(context: Context) {
        if (boxInstance != null) return
        
        val clientConfigJson = """
        {
          "inbounds": [{
            "type": "socks",
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "listen_port": $LOCAL_PROXY_PORT
          }],
          "outbounds": [{
            "type": "vless",
            "tag": "vless-out",
            "server": "IP_ВАШЕГО_СЕРВЕРА_В_СПБ",
            "server_port": 443,
            "uuid": "UUID_ПОЛЬЗОВАТЕЛЯ",
            "flow": "xtls-rprx-vision",
            "tls": {
              "enabled": true,
              "server_name": "telemost.yandex.ru",
              "reality": {
                "enabled": true,
                "public_key": "ПУБЛИЧНЫЙ_КЛЮЧ_СЕРВЕРА",
                "short_id": "SHORT_ID"
              }
            }
          }]
        }
        """.trimIndent()

        // Запуск инстанса Sing-box в фоновом потоке приложения
        boxInstance = SingBox.newBox(clientConfigJson)
        boxInstance?.start()
    }

    fun stopBypass() {
        boxInstance?.stop()
        boxInstance = null
    }
}
Шаг 2.3. Реализация переключателя (Toggle Bypass) в UI
Интегрировать в настройки приложения Switch (переключатель).

Алгоритм при изменении состояния Switch:

Если пользователь включает Switch -> Сохранить состояние в SharedPreferences -> Вызвать BypassManager.startBypass() -> Переинициализировать сетевой клиент мессенджера (HTTP/WebSocket) с использованием прокси 127.0.0.1:10808.

Если пользователь выключает Switch -> Сохранить состояние -> Вызвать BypassManager.stopBypass() -> Переинициализировать сетевой клиент на прямую работу с сервером (без прокси).

4. Часть 3. Адаптация сетевого уровня мессенджера
Переписать инициализацию сетевых клиентов (HttpClient, WebSocket, WebRTC), чтобы они динамически переключались на локальный порт Sing-box.

Шаг 3.1. Динамический HTTP / WebSocket Клиент (для PocketBase)
Если обход включен, клиент должен ходить на PocketBase через localhost.

Пример для OkHttpClient:

Kotlin
fun getOkHttpClient(isBypassEnabled: Boolean): OkHttpClient {
    val builder = OkHttpClient.Builder()
    
    if (isBypassEnabled) {
        // Указываем в качестве прокси локальный порт Sing-box
        builder.proxy(Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", BypassManager.LOCAL_PROXY_PORT)))
        // Адрес сервера теперь запрашивается через прокси, маскируясь под Яндекс
        builder.connectTimeout(15, TimeUnit.SECONDS)
    }
    
    return builder.build()
}
Шаг 3.2. Адаптация медиа-трафика (для Coturn)
Для звонков WebRTC (PeerConnection) динамически подставлять конфигурацию RTCConfiguration.

Обход выключен: Мессенджер берет стандартный URL вашего Coturn: turn:your-server-ip:3478.

Обход включен: Так как ТСПУ режет UDP, Sing-box на клиенте умеет заворачивать UDP в TCP-туннель Reality. Настроить в клиентском конфиге sing-box дополнительный outbound/inbound для проксирования UDP-трафика до Coturn через тот же защищенный порт 443.

5. План проверки для ИИ (Checklist)
После генерации кода ИИ должен верифицировать следующие этапы:

[ ] Проверка "на дурака" на сервере: При открытии IP-адреса сервера в браузере должна открываться страница Яндекс.Телемоста (редирект Reality).

[ ] Тест выключенного режима: При выключенном тумблере приложение успешно авторизуется в PocketBase напрямую (если нет блокировок).

[ ] Тест включенного режима: При включенном тумблере логи приложения показывают успешный хендшейк с telemost.yandex.ru, а PocketBase продолжает получать WebSocket-события.