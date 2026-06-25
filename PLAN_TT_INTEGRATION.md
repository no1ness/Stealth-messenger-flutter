# План интеграции telegram-tt с бэкендом Stealth

## Цель

Форкнуть telegram-tt (React/TypeScript) и заменить MTProto/GramJS слой на PocketBase + WebRTC (Stealth бэкенд). UI и стейт-менеджмент telegram-tt остаются без изменений.

## Архитектура

```
┌─────────────────────────────────────────────┐
│            telegram-tt UI (React)            │
│   ~400 компонентов, 0 изменений             │
└──────────────┬──────────────────────────────┘
               │ withGlobal() — подписка на store
               ▼
┌─────────────────────────────────────────────┐
│       Global Actions + Store + Reducers      │
│   ~50 файлов, минимальные изменения         │
└──────────────┬──────────────────────────────┘
               │ callApi('methodName', args) → Promise
               ▼
┌─────────────────────────────────────────────┐
│   callApi() → Worker (postMessage) —         │
│   СОХРАНЯЕТСЯ, не удалять                   │
└──────────────┬──────────────────────────────┘
               ▼
┌─────────────────────────────────────────────┐
│   src/api/stealth/ — НОВЫЙ СЛОЙ              │
│   PocketBase SDK + WebRTC вместо GramJS      │
│                                              │
│   methods/ — 27 файлов (~15k строк)          │
│   apiBuilders/ — конвертеры в Api* типы      │
│   apiUpdaters/ — обработка входящих событий   │
└─────────────────────────────────────────────┘
```

### Ключевые решения по архитектуре

- **Worker сохраняется** — воркер не часть GramJS, это архитектурный паттерн telegram-tt. Все вызовы API идут через `postMessage`. Меняется только имплементация внутри методов.
- **GramJS удаляется инкрементально** — не за один коммит. Сначала заменяются содержимое, потом удаляются неиспользуемые файлы.
- **Service worker адаптируется** — telegram-tt регистрирует SW для офлайн-кеша. Нужно заменить MTProto кеширование на Stealth API.

## Поверхность интеграции

### Что остаётся без изменений (можно переиспользовать):

| Компонент | Файлов | Строк | Причина |
|-----------|--------|-------|---------|
| UI компоненты | ~400 | ~100k | Чистый React, не зависит от бэкенда |
| Global store/reducers | ~80 | ~30k | Работает с Api* типами |
| Стейт-менеджмент (Teact) | ~20 | ~5k | Своя реализация |
| WebRTC вызовы (`vibecalls/`) | ~10 | ~3k | Уже WebRTC, заменить сигналинг |
| Worker (connector/worker.ts) | ~3 | ~0.7k | **Сохранить** — архитектурный паттерн |
| Selectors | ~15 | ~3k | Чистые функции |
| UI actions | ~20 | ~5k | Навигация, модалки |

### Что нужно написать/изменить заново:

| Компонент | Файлов | Строк | Замена |
|-----------|--------|-------|--------|
| **`src/lib/gramjs/`** | ~50 | ~10k | **Удалить** — весь MTProto стек (поэтапно) |
| **`src/api/gramjs/methods/`** | **27** | **~15k** | **Переписать** под PocketBase + WebRTC |
| `src/api/gramjs/apiBuilders/` | ~10 | ~3k | Конвертировать Stealth модели в Api* типы |
| `src/api/gramjs/gramjsBuilders/` | ~5 | ~2k | **Удалить** — не нужно без GramJS |
| `src/api/gramjs/updates/` | ~5 | ~2k | Заменить на PocketBase реалтайм |
| `src/api/types/` | ~18 | ~5k | **Почистить** — удалить Telegram-специфичные типы (stars, payments, statistics, business) |
| `src/lib/vibecalls/` сигналинг | ~3 | ~1k | Заменить MTProto сигналинг на PB SSE |
| `src/components/auth/` | ~6 | ~2k | **Переписать** — Stealth не использует phone+code |
| Service worker | ~3 | ~1k | **Адаптировать** под Stealth API |
| UI avatar компоненты | ~5 | ~1k | Инициалы (initials fallback) |

## План по фазам

### Фаза 0: Форк и настройка (4-5 дней)

1. Создать форк telegram-tt в отдельный репозиторий
2. Обновить `vite.config.ts` — убрать проверку `TELEGRAM_API_ID/HASH`, обновить env vars (CSP не трогать — уже разрешает все http/https; для production заменить `http: https:` на конкретный URL PocketBase)
3. Настроить env переменные для Stealth как `VITE_POCKETBASE_URL`, `VITE_TURN_URL` и т.д. (префикс VITE_ обязателен для Vite)
4. Заменить содержимое `src/lib/gramjs/` на заглушки с сохранением экспортов (поэтапное удаление)
5. Добавить PocketBase SDK для TypeScript (`npm install pocketbase`)
6. Создать пустой `src/api/stealth/` со структурой
7. Переключить `callApi()` с `src/api/gramjs/` на `src/api/stealth/`
8. Настроить базовый `initApi()` — подключение к PocketBase, авто-аутентификация
9. **NEW:** Адаптировать service worker:
   - Найти `src/serviceWorker.ts` (регистрация в `index.html` через Vite)
   - Убрать MTProto-specific cache strategies (network-only для API, stale-while-revalidate для медиа)
   - Оставить статический asset cache (JS chunks, CSS, fonts)
10. **NEW:** Сохранить воркер-архитектуру (не удалять worker/connector.ts)
11. **NEW:** Logging/error handling — заменить GramJS-specific (RPCError, FloodWait) на PocketBase ошибки
12. **NEW:** State cache — инкремент версии `GLOBAL_STATE_CACHE_KEY` в `cache.ts`; очистка старого кеша при несовпадении версии
13. **NEW:** CI/CD — настроить GitHub Actions (или аналог) для `npm run build:production` и деплоя форка на stealthpro.ru
14. **NEW:** Testing strategy — оценить какие vitest/playwright тесты сломаются; замокать PocketBase вместо GramJS; пометить telegram-specific тесты как skip

**Результат:** Приложение запускается в браузере без MTProto, все API вызовы падают с "not implemented".

### Фаза 0.5: Очистка типов (2 дня) — НОВАЯ

1. **NEW:** Пройтись по `src/api/types/` — удалить Telegram-специфичные модули:
   - `stars.ts` — Telegram Stars, Star Gifts
   - `payments.ts` — платежи, Premium, Giveaways, Invoices
   - `statistics.ts` — статистика каналов
   - `business.ts` — бизнес-локации, часы работы
   - `stories.ts` — истории (пока заглушка)
   - `bots.ts` — боты (пока заглушка)
   - `instantView.ts` — Instant View
2. **NEW:** Обновить `index.ts` — убрать реэкспорты удалённых типов
3. **NEW:** Проверить reducers и selectors на импорты удалённых типов; добавить `// @ts-ignore` или заглушки
4. **NEW:** i18n — telegram-tt загружает переводы через MTProto (`langpack.getLangPack`). Без MTProto UI покажет ключи (например, "lng_dialog_list"). Решение — (a) экспортировать `.strings` файл из `src/assets/localization/` и загружать локально, либо (b) реализовать `langpack.getLangPack` через PocketBase (приоритет — a, статический bundle)

**Результат:** Типовая система чистая, компиляция проходит без Telegram-специфичных зависимостей.

### Фаза 1: Аутентификация (5-6 дней)

1. Портировать `PocketBaseAuthService` на TypeScript:
   - Deterministic PB user id = SHA-256(Stealth UUID)[:15]
   - Генерация X25519 ключей при первой регистрации
   - **PB auth flow:** email = `<pbId>@stealth.local`, password = random 24-char, сохранённый в localStorage. Попытка `authWithPassword` → если ошибка — создать пользователя в PB с `id = expectedPbId`
   - Автоматический вход по токену из localStorage
   - **Browser key storage:** X25519 private key хранится в localStorage (base64). Риск XSS → кража ключей. Для production рассмотреть `crypto.subtle.wrapKey()` или IndexedDB. Минимально: предупреждение в документации.
2. **NEW:** Auth UI — написать заново:
   - Вместо phone+code: экран генерации идентичности (nickname)
   - После создания → сразу в чаты
   - Первый запуск vs повторный вход (токен в localStorage)
3. Реализовать заглушки для `callApi('initApi')`, `callApi('setAuthPhoneNumber/Code/Password')`

**Результат:** Можно залогиниться в Stealth, видеть пустой список чатов.

### Фаза 2: Модели данных и API типы (7-10 дней)

1. Создать `src/api/stealth/apiBuilders/`:
   - `buildApiUser()` — конвертирует user_profiles в `ApiUser`; `phoneNumber` = UUID (номеров в Stealth нет)
   - `buildApiChat()` — конвертирует чат из LocalDB в `ApiChat`
   - `buildApiMessage()` — конвертирует сообщение в `ApiMessage`; расшифровывает `content` → `ApiFormattedText`
2. **NEW:** `buildApiUserStatus()` — маппинг `isOnline + lastSeen` → `ApiUserStatus`
3. **NEW:** `buildApiFormattedText()` — парсинг plain text в `ApiFormattedText` (без rich text в MVP, но структура должна быть)
4. **NEW:** `downloadMedia()` stub — возвращает `null` для avatar хэшей, чтобы Avatar.tsx показывал инициалы
5. **NEW:** `mediaLoader.fetch()` адаптация — `downloadMedia()` вместо GramJS, с поддержкой `ApiMediaFormat.BlobUrl`
6. **NEW:** `localDb.ts` с Proxy/EventTarget (для событий изменений); решение по multi-tab: **single-tab только для MVP**
7. Создать `src/api/stealth/helpers/` — утилиты для PB
8. **NEW:** Определить минимальный набор `ApiUpdate` типов для MVP (~15 из 70):
   - `updateChat`, `updateChatLastMessage`, `newMessage`, `updateMessage`, `deleteMessages`, `deleteHistory`
   - `updateUser`, `updateUserStatus`, `updateChatTypingStatus`, `draftMessage`
   - `updateMessageSendSucceeded`, `updatePinnedIds`, `updateEntities`

**Результат:** Система типов готова, UI может отображать данные. Аватары — инициалы (без фото).

### Фаза 2.5: Crypto helpers (1 день) — НОВАЯ

**Вынесена перед apiBuilders — `buildApiMessage()` нужна расшифровка.**

**Важно:** Stealth использует **симметричную KDF цепочку** (не Signal Double Ratchet):
- `initializeChains(sharedSecret, myId, otherId)` → `mySendChain`, `theirSendChain` (через `HMAC-SHA256(sharedSecret, "CHAIN_1"/"CHAIN_2")`)
- `advanceSymmetricRatchet(chainKey)` → `messageKey = HMAC-SHA256(chainKey, [0x01])`, `nextChainKey = HMAC-SHA256(chainKey, [0x02])`
- `getNthMessageKey(chainKey, N)` → итерация advanceSymmetricRatchet N раз
- Нет DH ратчета, нет PFS, нет post-compromise security.

1. **NEW:** Портировать только decrypt-часть криптографии на TypeScript:
   - `decryptStealthMessage(encryptedBase64, ownPrivateKey, peerPublicKey)` → plaintext
   - Используется `apiBuilders/buildApiMessage()` для расшифровки content
2. **NEW:** `sharedSecretFromX25519(myPrivate, theirPublic)` → 32-byte sharedSecret
3. **NEW:** `aes256GcmDecrypt(base64Payload, secretKey)` → Uint8List
4. **NEW:** `ratchetGetMessageKey(chainKey, index)` — симметричная KDF цепочка (HMAC-SHA256)

**Зависимость:** Web Crypto API — требует HTTPS/localhost (secure context).

### Фаза 3: Сообщения и чаты (15-20 дней) — РАЗБИТА

#### Фаза 3a: Список чатов + создание (4-5 дней) — НОВАЯ
1. **NEW:** `fetchChats()` — читать все чаты из IndexedDB, для каждого найти последнее сообщение
2. **NEW:** `buildChatListActive()` — сортировка чатов по дате последнего сообщения (как Telegram)
3. **NEW:** Unread count — вычислить из `last_read_at` vs сообщения с `created_at > last_read_at`
4. `fetchFullChat()` — загружать метаданные чата
5. `searchChats()` — фильтр по локальным контактам
6. **NEW:** `createChat(memberIds, title, isPrivate)` — генерация UUID чата, сохранение в IndexedDB, вызов `ensureSignaling()` для P2P. Возвращает `ApiChat` с синтетическим id.

**Результат:** Левый сайдбар показывает список чатов с именем, последним сообщением, unread счётчиком, временем.

#### Фаза 3b: Отправка сообщений (8-10 дней)
1. **NEW:** Портировать encrypt-часть криптографии на TypeScript:
   - X25519 shared secret через `@noble/curves`
   - AES-256-GCM encrypt через Web Crypto API
   - Ratchet KDF (HMAC-SHA256) через Web Crypto API
   - Формат: `base64(nonce[12] || ciphertext || mac[16])`
2. **NEW: RTCPeerConnection lifecycle management:**
   - Создание `RTCPeerConnection` при открытии чата (ICE STUN/TURN из config)
   - Закрытие при переключении на другой чат
   - Менеджер активных соединений: `Map<chatId, RTCPeerConnection>`
3. **NEW: PocketBase SSE signaling:**
   - Подписка на `rtc_signaling` с фильтром `roomId=chatId && target=pbSelfId`
   - Отправка offer/answer/ICE candidate через PB
   - Обработка hangup (peer disconnected)
4. **NEW: DataChannel messaging:**
   - `pc.createDataChannel('messaging')` для исходящих
   - `pc.ondatachannel` для входящих
   - Формат фрейма: `{ id, chat_id, sender_id, content (encrypted), message_type, reply_to_id, metadata: { encryption: 'e2e'|'group_e2e', sender_ratchet_index: N }, created_at }`
   - ACK-подтверждения: `{ type: 'ack', messageId }`
5. **NEW: Retry worker:**
   - Exponential backoff: 1→2→4→8→16→30s (макс 5 попыток)
   - Multi-tab anti-double-retry guard (30s)
   - `messageSendingStatePending` пока retry, `messageSendingStateFailed` при исчерпании
   - User-initiated retry: `retryNow(messageId)`
6. **NEW:** Delivery status mapping:
   - Stealth: pending → sent → delivered
   - telegram-tt: `messageSendingStatePending`, затем снять при ACK
   - failed при превышении retry
7. `sendMessage(text, replyToMsgId?)` — зашифровать → отправить в DataChannel (с `reply_to_id` если есть) → сохранить в IndexedDB
8. `editMessage()`, `deleteMessages()` — через DataChannel + локально

**Результат:** Можно отправлять текстовые сообщения. Статусы доставки отображаются.

#### Фаза 3c: Получение сообщений + real-time (3-4 дня)
1. Подписка на PocketBase Realtime (SSE) на `rtc_signaling`
2. **NEW:** Получение входящих P2P сообщений — собрать DataChannel, расшифровать, сохранить в IndexedDB
3. `sendApiUpdate({ '@type': 'updateChat', ... })` → store → UI
4. **NEW:** Обновление unread count при получении нового сообщения
5. **NEW:** ACK — отправлять при получении сообщения

**Результат:** Сообщения приходят в реальном времени, UI обновляется.

#### Фаза 3d: Рендеринг сообщений (5-7 дней) — НОВАЯ
1. **NEW:** Rich text — telegram-tt рендерит `ApiFormattedText` с entities (bold, italic, link). В MVP — plain text только, структуру оставить.
2. **NEW:** Synthetic message ID — telegram-tt использует `id: number` (sequential). Stealth использует UUID. Нужен `Map<uuid, sequentialInt>` при загрузке из IndexedDB.
3. **NEW:** Delivery icons — telegram-tt показывает иконки: pending (часы) → sent (одна галочка) → read (две галочки). Сопоставить pending/sent/delivered.
4. **NEW:** Date формат — telegram-tt использует relative time + absolute time на следующий день. Должно работать из коробки, т.к. использует unix timestamp.
5. **NEW:** Поиск сообщений — `searchMessagesGlobal()`, `searchMessagesInChat()` через IndexedDB (поиск по plaintext content)

**Результат:** Сообщения отображаются как в Telegram: время, статус, отправитель.

### Фаза 4: Контакты и пользователи (4-6 дней)

**Перенесена перед Фазой 3a** — список чатов зависит от имён контактов.

1. `fetchContactList()` — читать из PocketBase `user_profiles`
2. `fetchUsers()` — получать информацию о пользователях
3. `importContact()`, `deleteContact()` — через PB
4. **NEW:** Contact addition UI — парсер `stealth:<base64url({v, user_id, name, public_key})>` из буфера обмена или QR-кода. Добавление контакта по никнейму (поиск через PB `user_profiles`).
5. `searchContacts()` — поиск по никнейму/public key
6. **NEW:** `presenceUpdate()` — PB SSE подписка на `user_profiles` → `sendApiUpdate({ '@type': 'updateUserStatus', ... })`
7. **NEW:** `buildApiUserStatus()` — конвертация `isOnline`/`lastSeen` → `{ wasOnline: timestamp }` или `{ isOnline: true }`

**Результат:** Полноценный список контактов с онлайн-статусом.

### Фаза 5: Файлы и вложения (8-10 дней)

1. Портировать `AttachmentService` на TypeScript:
   - Chunked transfer через WebRTC DataChannels (для больших файлов), размер чанка **64KB**
   - Fallback: файлы <2MB можно передавать через PocketBase `rtc_signaling` поле
   - Формат chunk: `{ type: 'blob-chunk', blobId, seq, total, hash, fileName, mime, bytes: base64 }`
   - LRU кэш на IndexedDB
   - **Attachment descriptor format:** content поля сообщения может содержать `local-attachment:<base64url({v, blobId, hash, size, mime, fileName})>`. `buildApiMessage()` должен парсить этот префикс → `hasMedia = true`.
2. **NEW:** `uploadFile()` в telegram-tt format — разбить на chunks, отправить через DC
3. **NEW:** `downloadMedia()` — собрать chunks, сохранить blob (memory/IndexedDB), отдать `BlobUrl` для UI. Поддержка `ApiMediaFormat.BlobUrl`, `ApiMediaFormat.File`.
4. **NEW:** `mediaLoader` интеграция — telegram-tt использует `mediaLoader.fetch(mediaHash, format)` для кеширования и вызова `downloadMedia()`. Нужен адаптер.
5. **NEW:** Фото viewer — уже есть в telegram-tt, должен работать если `downloadMedia()` возвращает `BlobUrl`
6. **NEW:** Аватары — **initials только для MVP**. Stealth не имеет серверных аватарок. avatarPhotoId = null всегда. В будущем: P2P transfer avatar при открытии чата (первое сообщение с `local-attachment:` от пользователя).

**Результат:** Работают фото, документы, голосовые.

### Фаза 6: Звонки (5-7 дней)

1. Заменить сигналинг звонков (начальный handshake): MTProto → PocketBase `rtc_signaling`
   - `requestCall()` / `acceptCall()` → создание/обновление записи в `rtc_signaling`
   - ICE candidate relay — уже через WebRTC API, не через MTProto
   - `vibecalls/` уже использует WebRTC — менять только начальный offer/answer exchange
2. Портировать логику из `IncomingCallService`:
   - Получение offer через PB SSE
   - Показ входящего звонка (UI уже есть)
   - ICE candidate exchange через PB
3. Портировать шифрование медиа (DTLS-SRTP — стандартный WebRTC)
4. **NEW:** `getUserMedia()` для доступа к микрофону/камере — требует HTTPS (secure context)

**Результат:** Аудио/видео звонки.

### Фаза 7: Групповые чаты (3-5 дней) — НОВАЯ, РАСШИРЕНА

1. **NEW:** Базовая модель группы: `is_private: false, members[], roles{ userId: 'admin'|'member' }`
2. **NEW:** Групповое шифрование: AES-256-GCM с per-group ключом. При создании группы генерируется random 32-byte key, шифруется X25519 для каждого участника, передаётся через DataChannel в metadata первого сообщения группы.
3. **NEW:** Создание группы — адаптировать UI telegram-tt
4. **NEW:** Добавление/удаление участников — через DataChannel + локальное обновление
5. **NEW:** Telegram UI для групп сложное (темы форума, права, админы) — для MVP: минимальная поддержка

**Результат:** Базовые групповые чаты (создание, отправка, участники).

### Фаза 8: Остальные фичи (5-7 дней)

1. Настройки — локальные (тема, уведомления)
2. Стикеры — убрать или заменить на свои
3. Emoji — оставить встроенные
4. Поиск — по локальным сообщениям
5. Удаление аккаунта / logout — clear localStorage (ключи, токен, сообщения, чаты, контакты) → redirect на auth screen. При удалении аккаунта: delete PB user + clear local data.
6. Dashboard интеграция (опционально)
7. **NEW:** Safety number — `SHA-256(ownPublicKey + peerPublicKey)[:32]` base64 для верификации контакта. Показать в UserDetail screen.

## Оценка времени (обновлённая)

| Фаза | Дней | Зависимости |
|------|------|-------------|
| 0. Форк + настройка (SW, CI/CD, cache, testing, env vars) | 4-5 | — |
| 0.5. Очистка типов + i18n | 2.5 | Фаза 0 |
| 1. Аутентификация (key storage, PB auth flow) | 5-6 | Фаза 0.5 |
| 2. Модели данных + apiBuilders | 7-10 | Фаза 1 |
| 2.5. Crypto helpers (Symmetric Ratchet KDF) | 1 | Фаза 2 |
| 4. Контакты | 4-6 | Фаза 2.5 |
| 3a. Список чатов + создание | 4-5 | Фаза 4 |
| 3b. Отправка сообщений (DataChannel frame) | 8-10 | Фаза 3a |
| 3c. Получение + real-time | 3-4 | Фаза 3b |
| 3d. Рендеринг сообщений + поиск | 5-7 | Фаза 3c |
| 5. Файлы и вложения (descriptor format, 64KB chunks) | 8-10 | Фаза 3b |
| 6. Звонки | 5-7 | Фаза 3b |
| 7. Групповые чаты | 3-5 | Фаза 4 |
| 8. Остальное (+ safety number) | 5-7 | Фаза 2 |
| **Итого** | **67-102** | |

**Оптимистично:** ~10 недель (полный день)
**Реалистично:** ~14 недель
**С учётом отладки:** ~16-20 недель

## Ключевые решения

### 1. TypeScript PocketBase SDK
```bash
npm install pocketbase
```
SDK предоставляет: auth, CRUD, realtime, файлы.

### 2. Портировать криптографию
Stealth использует:
- X25519 (ключи) → `@noble/curves`
- AES-256-GCM (шифрование сообщений) → Web Crypto API
- Symmetric Ratchet KDF (HMAC-SHA256) → Web Crypto API

Формат: `base64(nonce[12] || ciphertext || mac[16])`

### 3. WebRTC DataChannels
В браузере доступен нативно:
- `RTCPeerConnection` с ICE STUN/TURN
- `DataChannel` для сообщений
- PocketBase SSE для сигналинга

### 4. IndexedDB для локального хранения
telegram-tt уже использует IndexedDB. Stealth тоже. Адаптировать схему:
- `messages` (autoIncrement, index: chatId, deliveryStatus)
- `chats` (keyPath: id)
- `contacts` (keyPath: contact_user_id)

### 5. Worker-архитектуру НЕ удаляем
Воркер — архитектурный паттерн telegram-tt. `callApi()` шлёт сообщения в воркер через `postMessage`. Удаление воркера потребует переписывания `src/api/gramjs/index.ts` и всех action handlers. Воркер остаётся, меняется только имплементация методов.

### 6. Auth UI переписывается
Stealth не использует номера телефонов. Экран логина заменяется на:
- Первый запуск: ввод nickname → генерация X25519 ключей + UUID
- Повторный вход: чтение токена из localStorage → auto-auth

### 7. Avatar стратегия
Stealth не имеет серверных аватарок. **initials только для MVP** — `downloadMedia()` stub → null → Avatar.tsx показывает инициалы (работает из коробки). В будущем: P2P transfer при открытии чата (первое сообщение с `local-attachment:` от пользователя).

### 8. Synthetic message ID
telegram-tt использует `id: number` (sequential, from MTProto). Stealth использует `id: UUID`.
При загрузке из IndexedDB: `Map<uuid, sequentialInt>` генерируется на лету.

### 9. Single-tab only для MVP
telegram-tt поддерживает multi-tab (BroadcastChannel). Stealth — single-tab только.
В будущем можно добавить BroadcastChannel для cross-tab sync.

### 10. Secure Context requirement
Web Crypto API + getUserMedia + RTCPeerConnection требуют HTTPS (или localhost в dev).

## Риски (обновлённые)

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| telegram-tt обновится — конфликт слияния | Высокая | Среднее | Минимизировать изменения в UI части |
| WebRTC DataChannel нестабилен в браузерах | Средняя | Среднее | Fallback через PB polling |
| Производительность больших чатов | Средняя | Низкое | Виртуализация списка (уже в telegram-tt) |
| telegram-tt использует устаревшие API | Низкая | Низкое | Полифиллы |
| Размер сборки ~3MB | Средняя | Низкое | Tree-shaking неиспользуемых типов |
| Worker архитектура сломается при замене GramJS | Высокая | Высокое | Менять инкрементально, не удалять сразу |
| Service worker без MTProto | Средняя | Среднее | Адаптировать SW, убрать MTProto-зависимые кеш-стратегии |
| Auth UI интеграция сложнее ожидаемой | Средняя | Среднее | Не переписывать все Auth компоненты, только заменить логику |
| **NEW:** `downloadMedia()` обязательна для avatar — без неё UI не крашится (initials fallback) | Средняя | Среднее | Stub в Phase 2, full реализация в Phase 5 |
| **NEW:** Web Crypto API требует HTTPS (secure context) | Низкая | Среднее | dev: localhost OK; prod: HTTPS mandatory |
| **NEW:** Multi-tab sync через BroadcastChannel — не нужно для MVP | Низкая | Низкое | Single-tab только для MVP |
| **NEW:** Synthetic message ID (Stealth UUID → telegram-tt number) | Средняя | Среднее | Map при загрузке из IndexedDB |
