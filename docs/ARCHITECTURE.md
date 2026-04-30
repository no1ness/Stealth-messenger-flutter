# Архитектура Stealth Messenger

## Обзор

Stealth Messenger — кроссплатформенный безопасный мессенджер (Android, Web) на Flutter. Ключевые принципы: **local-first хранение**, **E2E-шифрование**, **P2P-аудио- и видеозвонки через WebRTC**, **сигналинг звонков через PocketBase (SSE на 443/TLS)**, **Supabase только как резервное/синхронизирующее хранилище для контактов и истории**.

## Модель данных: Local-First

```
┌─────────────────────────────────────────────────────────┐
│  PRIMARY: LocalDatabaseService (idb_shim + AES-256-GCM) │
│  ├── messages  — зашифрованные сообщения на устройстве  │
│  └── chats     — кеш чатов для offline-доступа          │
├─────────────────────────────────────────────────────────┤
│  BACKUP: Supabase (PostgreSQL + Realtime + Storage)      │
│  ├── синхронизация при наличии сети                      │
│  ├── публичные ключи пользователей                       │
│  ├── история звонков (записи, не сигналинг)              │
│  └── зашифрованные медиафайлы (Storage)                  │
├─────────────────────────────────────────────────────────┤
│  SIGNALING: PocketBase (SQLite + Realtime SSE)           │
│  ├── коллекция rtc_signaling                             │
│  ├── события offer / answer / candidate / hangup         │
│  ├── фильтр на сервере: target='<selfUserId>'            │
│  └── развёртывание: своё DNS-имя на 443/TLS              │
└─────────────────────────────────────────────────────────┘
```

### Режимы работы

| Режим | Описание | Управление |
|-------|----------|------------|
| **Online (по умолчанию)** | Читает из Supabase, всегда пишет локально + в Supabase | `useSupabase = true` |
| **Offline / работа без сервера** | Читает и пишет только локально | `useSupabase = false` |
| **Деградация** | При ошибке Supabase автоматический fallback на локальную БД | Прозрачно для пользователя |

`useSupabase` хранится в `SharedPreferences`. Устанавливается в `false` через кнопку **«Работать оффлайн»** на экране `StartupErrorScreen`.

## Архитектурные слои

```
┌──────────────────────────────────────────────────┐
│  UI Layer (Flutter)                              │
│  ├── Screens (chats, contacts, profile, settings)│
│  ├── Widgets (chat_bubble, message_input, ...)   │
│  └── Theme (Apple Liquid — glassmorphism)         │
├──────────────────────────────────────────────────┤
│  Service Layer                                   │
│  ├── SupabaseService (чаты, контакты, сообщения) │
│  ├── LocalDatabaseService (primary storage)      │
│  ├── P2PService (WebRTC DataChannel messaging)   │
│  ├── StorageService (платформенное хранилище)    │
│  ├── WebRtcSignalingService (PocketBase SSE)     │
│  ├── IncomingCallSignalingService (глобальная подписка) │
│  └── WebRTC Support (звонки, диагностика)        │
├──────────────────────────────────────────────────┤
│  Crypto Layer                                    │
│  ├── X25519 (обмен ключами Diffie-Hellman)       │
│  ├── AES-256-GCM (шифрование сообщений)          │
│  ├── Double Ratchet (forward secrecy)            │
│  └── Group Key Envelopes (групповые ключи)       │
├──────────────────────────────────────────────────┤
│  Backend (Supabase) — резервное хранилище        │
│  ├── PostgreSQL (users, chats, messages, ...)    │
│  ├── Realtime (подписки на сообщения, typing)    │
│  ├── Storage (chat-media — зашифрованные файлы)  │
│  └── история звонков (record/markIncomingCallDeclined/...) │
├──────────────────────────────────────────────────┤
│  Backend (PocketBase) — сигналинг звонков         │
│  ├── SQLite + Go runtime (single binary)         │
│  ├── Realtime (SSE подписка на rtc_signaling)    │
│  └── развёртывание: docs/POCKETBASE_SETUP.md     │
└──────────────────────────────────────────────────┘
```

## Структура проекта

```
client/
├── lib/
│   ├── main.dart                  # Точка входа; StartupErrorScreen с offline-mode
│   ├── main_tabs.dart             # Навигация (4 таба)
│   ├── registration_screen.dart   # Генерация ключей, регистрация
│   ├── supabase_service.dart      # Основной сервис (чаты, крипто, звонки)
│   ├── local_database_service.dart# Primary storage (idb_shim + AES-256-GCM)
│   ├── p2p_service.dart           # WebRTC DataChannel для offline-messaging
│   ├── p2p_discovery_service.dart # Обнаружение пиров
│   ├── storage_service*.dart      # Платформенное хранилище ключей
│   ├── webrtc_support*.dart       # WebRTC-абстракция
│   ├── helpers/                   # Платформенные хелперы (crypto_helper, ...)
│   ├── themes/apple_liquid/       # Дизайн-система (glassmorphism)
│   └── ui/
│       ├── screens/               # Экраны (18 файлов)
│       └── widgets/               # Виджеты (7 файлов)
├── test/
│   └── crypto_test.dart           # Тесты E2E-шифрования
└── supabase_migrations/           # SQL-миграции (8 файлов)
```

## Схема базы данных

```mermaid
erDiagram
    users {
        uuid id PK
        text nickname
        text public_key
        timestamp created_at
        timestamp updated_at
    }
    
    chats {
        uuid id PK
        text name
        boolean is_private
        timestamp created_at
        timestamp updated_at
    }
    
    chat_members {
        uuid chat_id FK
        uuid user_id FK
        timestamp joined_at
        timestamp last_read_at
        boolean typing
    }
    
    messages {
        uuid id PK
        uuid chat_id FK
        uuid sender_id
        text content
        text message_type
        uuid reply_to_id
        timestamp created_at
        jsonb metadata
        timestamp edited_at
        timestamp deleted_at
    }
    
    contacts {
        uuid id PK
        uuid user_id FK
        uuid contact_user_id FK
        text name
    }
    
    group_key_envelopes {
        uuid chat_id FK
        uuid user_id FK
        uuid wrapped_by_user_id
        text encrypted_key
        timestamp updated_at
    }
    
    pinned_messages {
        uuid chat_id FK
        uuid message_id FK
        uuid pinned_by_user_id
    }
    
    call_history {
        uuid id PK
        uuid chat_id FK
        uuid initiator_user_id
        uuid recipient_user_id
        text direction
        text status
        timestamp started_at
        timestamp answered_at
        timestamp ended_at
        jsonb metadata
    }

    users ||--o{ contacts : "has"
    users ||--o{ chat_members : "member_of"
    chats ||--o{ chat_members : "has"
    chats ||--o{ messages : "contains"
    chats ||--o{ pinned_messages : "pins"
    chats ||--o{ group_key_envelopes : "keys"
    chats ||--o{ call_history : "calls"
```

## Потоки данных

### Регистрация
1. Генерация UUID v4 (user_id) локально
2. Генерация пары ключей X25519 (публичный/приватный)
3. Приватный ключ → `StorageService` (secure storage)  
4. Публичный ключ → `users.public_key` в Supabase

### Отправка сообщения (online)
1. Вычисление `ratchetIndex` из Supabase (точный счётчик)
2. Шифрование: `AES-256-GCM(message, sharedSecret)` → `nonce + ciphertext + mac`
3. Base64-кодирование → `messages.content`
4. **Сохранение в `LocalDatabaseService`** (всегда)
5. Отправка в `Supabase.messages` (если `useSupabase = true`)

### Отправка сообщения (offline / `useSupabase = false`)
1. Вычисление `ratchetIndex` из локальной БД
2. Шифрование идентично online-режиму
3. **Сохранение только в `LocalDatabaseService`**
4. При восстановлении сети — синхронизация не реализована (будущая задача)

### Получение сообщений
1. Если `useSupabase = true`: читаем из Supabase, кешируем каждое сообщение локально
2. Если `useSupabase = false`: читаем из `LocalDatabaseService`
3. При ошибке Supabase: автоматический fallback на `LocalDatabaseService`

### Получение чатов
- При успешном запросе к Supabase — каждый чат сохраняется в `_localDb.saveChat()`
- При ошибке — `getChats()` возвращает данные из `_localDb.getChats()`

### WebRTC-звонок (аудио или видео)
1. Старт из экрана **Контакты**: caller сразу шлёт `offer` через PocketBase. Сам `offer` = факт входящего звонка (отдельного `call_initiation` нет).
2. На каждом устройстве `IncomingCallSignalingService` держит глобальную SSE-подписку на коллекцию `rtc_signaling` с фильтром `target='<selfUserId>' && (type='offer' || type='hangup')`. Когда приходит `offer`, `CallManager` показывает диалог.
3. После Answer — `WebRTCCallScreen` открывается с уже принятым offer (`initialOffer`), сразу делает `setRemoteDescription` → `createAnswer` → шлёт `answer` обратно через `WebRtcSignalingService`. Это убирает race condition «callee подписался слишком поздно».
4. ICE-кандидаты идут через ту же коллекцию (`type='candidate'`) с фильтром `roomId + target`. Hangup — отдельное событие `type='hangup'`, гарантированно закрывает экран на обеих сторонах в течение ~1 сек.
5. Прямое P2P-медиа через STUN/TURN/TURNS (медиа НЕ проходит через PocketBase). TURNS на 443/TLS — обход ТСПУ.
6. Конфигурация в `client/.env`: `POCKETBASE_URL` (обязательно), `TURN_URL` / `TURN_USERNAME` / `TURN_PASSWORD`, `TURNS_URL` / `TURNS_USERNAME` / `TURNS_PASSWORD`. Развёртывание сервера — `docs/POCKETBASE_SETUP.md`.

### P2P DataChannel (экспериментально)
- `P2PService` устанавливает WebRTC DataChannel для прямой передачи сообщений
- При открытом канале — сообщения идут P2P + кешируются локально
- При недоступности канала — fallback на `SupabaseService.sendMessage`

## Шифрование локальной БД

`LocalDatabaseService` хранит все данные в зашифрованном виде:
- Уникальный ключ `local_db_key` (AES-256) генерируется при первом запуске
- Ключ хранится в `StorageService` (Android Keystore / Secure Storage)
- Каждая запись: `{ payload: AES-GCM(jsonEncode(message)), chatId, timestamp }`

## Платформенная адаптация

| Компонент | Android (IO) | Web |
|-----------|-------------|-----|
| Хранилище ключей | `flutter_secure_storage_x` (Keystore) | `SharedPreferences` (localStorage) ⚠️ |
| Локальная БД | `idb_shim` + `sembast_io` | `idb_shim` + IndexedDB |
| WebRTC | `flutter_webrtc` (native) | `flutter_webrtc` (браузерный API) |
| Файлы | `dart:io` File | File API через `file_picker` |
| Навигация | Material с нативными жестами | Адаптивный layout (960+ → desktop) |
