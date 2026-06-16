# M18 — Performance оптимизация: скорость, плавность, юзер экспириэнс

**Branch:** `feature/optimize-code-speed-smoothness-ux`
**Created:** 2026-06-16
**Refined:** 2026-06-16 (пятая итерация /aif-improve)

## Settings

| Параметр | Значение |
|---|---|
| Testing | Включить тесты (unit + widget, где применимо) |
| Logging | Verbose (DEBUG) |
| Docs | Да — чекпоинт производительности |
| Roadmap linkage | M18 — Performance оптимизация |

## Roadmap Linkage

- **Milestone:** M18 — Performance оптимизация
- **Rationale:** Пользователи сообщают о задержках, подвисаниях и дропе кадров. Аудит выявил три слоя проблем: (1) тяжёлые перестроения UI на main isolate из-за `setState` без мемоизации, (2) последовательная криптография и полная загрузка БД на main isolate, (3) дорогие шейдеры/эффекты Apple Liquid design system.

## Архитектура решения

### Проблемы (по результатам аудита)

| Слой | Проблема | Влияние |
|---|---|---|
| **UI/main thread** | `chats_screen.dart` 1094 строки — god-класс с 28 полями, `setState()` перестраивает всё дерево; поиск без кеширования фильтрации | Лишние rebuilds при каждом keystroke / unrelated state change |
| **UI/paint** | GrainOverlay, ScanlineOverlay — BackdropFilter поверх ReorderableListView; CircuitBoardBackground — CustomPainter без кеширования | Просадка GPU при скролле длинных списков |
| **Data** | `getMessages()` возвращает ВСЕ сообщения — пагинация в памяти (skip/take); `fetchLastMessage` загружает 1000 | Фризы при открытии чата с 1000+ сообщений |
| **Crypto** | AES-GCM + X25519 sequential `await` на main isolate — 40 расшифровок подряд = ~20ms main isolate time | Микро-фризы при загрузке сообщений |
| **Pattern** | `ContactService.getNicknameForUser()` — загружает ВСЕ контакты циклом для каждого запроса; `_getOtherUserId()` — per-message lookup чата | Квадратичная сложность O(n*m) |
| **Memory** | `LocalAppService()` — 16 call sites, каждый создаёт новый инстанс с воркерами; `P2PDiscoveryService._peerController` не закрывается | Рост памяти, дублирование воркеров |
| **Architecture** | ChatListPanel и InsightPanel уже вынесены, но не подключены; нет DI | Затруднён рефакторинг |

### Подход

**Принцип:** снижение нагрузки на main isolate + GPU pipeline без изменения пользовательского опыта. Никаких изменений вёрстки/поведения — только внутренние оптимизации.

**Стратегия:**
1. **Phase 1 (Quick wins):** поиск с debounce + кешированием фильтрации, InsightPanel swap + search bar extract
2. **Phase 2 (Data):** пагинация БД, batch resolve N+1, вынести bulk-криптографию в isolate
3. **Phase 3 (GPU):** ScanlineOverlay Picture cache, BackdropFilter reduction на bubbles, ChromaticAberration ghost расширение
4. **Phase 4 (Architecture):** LocalAppService singleton, StreamController close, dispose audit
5. **Phase 5 (Startup):** defer сетевых операций после первого фрейма
6. **Phase 6 (Low priority):** CircuitBoard кеш, PresenceService опционально, ChatListPanel resolution, DecryptText, benchmark gates

---

## Tasks

### Phase 1: Quick wins — перестроения UI

#### Task 1 — Search в chats_screen: кеширование фильтрации + debounce message search

**Файл:** `client/lib/ui/screens/chats_screen.dart`

**Проблема (2 issues):**
1. **Message search без debounce** (строка ~774): `onSearchChanged: () => setState(...)` на каждый символ. Chat list search УЖЕ имеет 200ms debounce (строка 651).
2. **Фильтрация в `build()` без кеширования** (строки 521-544): `filteredChats` и `visibleMessages` — локальные переменные, пересчитываются при каждом `setState` (даже от `_isOtherTyping`, `_replyToMessageId` и т.д.)

**Решение:**
1. Добавить 200ms debounce для message search (по аналогии с chat search)
2. Заменить inline-фильтрацию на `_filteredChats` / `_filteredMessages` — поля состояния, которые обновляются только при изменении query или source-списка
3. Добавить debounce 500ms для `_loadChats()` — сейчас `unawaited(_loadChats())` (строка 93) вызывается на каждое P2P-сообщение, перечитывая все чаты из БД

**Критерии:**
- message search: `setState` не чаще 3 раз/сек при быстром наборе
- rebuild по `_isOtherTyping`: `filteredChats` не пересчитывается

**Тесты:**
- Widget test: 10 символов за 500ms → ≤2 вызова `setState` для message search

---

#### Task 2 — Переключиться на InsightPanel + extract search bar

**Файл:** `client/lib/ui/screens/chats_screen.dart`, `client/lib/ui/screens/chats/insight_panel.dart`

**Проблема:** 28 полей состояния в одном `StatefulWidget` — любой `setState` перестраивает всё дерево.

**Решение:**
1. **Подключить уже существующий `InsightPanel`** — он вынесен в `insight_panel.dart` но не используется. Тривиальная замена: 3 параметра (`messageCount`, `visibleChatCount`, `myUserId`). Удалить `_buildInsightPanel`, `_InsightTile`, лишний `kIsWeb` import.
2. **Extract search bar** в отдельный `StatefulWidget` или `StatelessWidget` с debounce timer — сейчас он inline в `_buildChatListPanel`.
3. `ChatListPanel` (из `chat_list_panel.dart`) **НЕ подключать** — аудит выявил 7 blocker-ов: type mismatch `onSelectChat`, missing `onSearchChanged`, missing `initials`, visual regression (skeleton vs spinner), другой виджет `_ChatTile` (hardcoded стили), разные цвета бейджей, отсутствует AccessibilityIds. Отложено в Phase 6 (Task 2b).

**Критерии:**
- `InsightPanel` заменяет inline `_buildInsightPanel` — визуально идентично
- search bar — изолирован от `chats_screen`

**Тесты:**
- Golden test: InsightPanel визуально идентичен старому `_buildInsightPanel`
- Widget test: search bar rebuild изолирован

---

### Phase 2: Data layer — пагинация, batch resolve, isolates

#### Task 3 — Пагинация messages

**Файлы:**
- `client/lib/local_database_service.dart` — `getMessages()` (строка 238)
- `client/lib/services/messaging/message_service.dart` — `getMessages()` (строка 181), `fetchLastMessage()` (строка 199)

**Проблема:**
- `LocalDatabaseService.getMessages(chatId)` открывает курсор IndexedDB и возвращает **все** сообщения (без лимита)
- `MessageService.getMessages()` вызывает его, потом применяет `.skip(offset).take(limit)` в памяти
- `fetchLastMessage()` вызывает `getMessages(chatId, limit: 1000)` — всё равно загружает все строки
- `fetchLastMessage()` используется при загрузке каждого чата в списке (N+1 по чатам)

**Решение:**
1. Добавить `getMessages(chatId, {int limit = 50, String? cursor})` — пагинированный запрос через курсор IndexedDB
2. `MessageService.getMessages()` передаёт cursor вниз, не загружает все
3. `fetchLastMessage()` — заменить на выделенный запрос `getLastMessage(chatId)`, не загружающий всю историю
4. На клиенте: `PaginationController<Message>` — хранит загруженные страницы + cursor
5. **Write-оптимизация:** split `saveMessage()` на `insertMessage` (без dedup `getKey`) + `upsertMessage` (с dedup). Группировать `saveMessage` + `saveChat` + `deliveryStatus` в одну IndexedDB транзакцию в `sendMessage()`.

**Критерии:**
- Загрузка чата с 2000 сообщений: initial render < 5ms (вместо ~150ms)
- Память: ≤ 100 сообщений в heap одновременно при скролле

**Тесты:**
- Unit test: `PaginationController` подгружает следующую страницу по cursor
- Unit test: `getLastMessage()` возвращает только одно сообщение

**Зависимость:** Должен быть выполнен ДО Task 5 (N+1) — `fetchLastMessage` будет переписан здесь.

---

#### Task 4 — Batch resolve N+1 user/contact lookups

**Файлы:**
- `client/lib/services/messaging/message_service.dart` — `_getOtherUserId()` (строка 551), `_isGroupChat()` (строка 562), `decryptRawMessage()` (строка 129)
- `client/lib/services/contacts/contact_service.dart` — `getNicknameForUser()` (строка 61), `getOtherPublicKey()` (строка 92), `getNicknames()` (строка 55)

**Проблема (4 N+1 паттерна):**

1. **`_getOtherUserId()` per-message (message_service.dart:159):** Для каждого расшифрованного сообщения вызывается `_getOtherUserId()`, который загружает чат из БД и перебирает членов. Результат не меняется для чата — достаточно вычислить один раз.

2. **`_isGroupChat()` per-send (message_service.dart:562):** При отправке/редактировании каждого сообщения загружает чат из БД дважды (`getChatById` + `getChatMemberIds`).

3. **`ContactService.getNicknameForUser()` (contact_service.dart:61):** Загружает `getContacts()` — всех контактов из БД — и перебирает циклом для каждого `userId`. `getNicknames()` вызывает это в цикле (N+1 внутри N+1).

4. **`ContactService.getOtherPublicKey()` (contact_service.dart:92):** Аналогично — загружает всех контактов и перебирает.

**Решение:**
1. `_getOtherUserId()` — закешировать результат для chatId (один раз за session)
2. `_isGroupChat()` — закешировать, переиспользовать флаг isPrivate из запроса
3. `getNicknameForUser()` — batch: собрать все userIds из порции сообщений, один `getContacts()` → построить `Map<userId, nickname>` в памяти
4. `getOtherPublicKey()` — batch: собрать все userIds, один запрос, построить `Map<userId, publicKey>`

**Критерии:**
- Загрузка порции 50 сообщений: 0 per-message запросов к БД (все resolve batch)
- `getNicknameForUser()` и `getOtherPublicKey()` — не вызывают `getContacts()` чаще 1 раза per batch

**Тесты:**
- Unit test: cache hit для `_getOtherUserId()`
- Performance test: замерить количество вызовов `getContacts()` при загрузке 50 сообщений

**Зависимость:** После T3 (пагинация) — T3 переписывает `fetchLastMessage`, что меняет код рядом с N+1.

---

#### Task 5 — Bulk crypto в isolate

**Файлы:** `client/lib/crypto/` (все файлы), `client/lib/services/messaging/message_service.dart`

**Проблема:** `MessageService.getMessages()` (строка 186-197) вызывает `decryptRawMessage()` для каждого сообщения последовательно через `Future.wait`. Хотя `dart:cryptography` — async API (FFI, не блокирует UI напрямую), 40+ последовательных вызовов AES-GCM + X25519 DH потребляют ~10-20ms main isolate time → микро-фриз при загрузке чата.

**Решение:**
1. Создать `CryptoIsolateService` — обёртка над `compute()` (top-level функция) для batch-операций. **Важно:** в коде 0 существующих использований isolate — `compute()` предпочтительнее (проще), `Isolate.spawn` только если нужен долгоживущий isolate.
2. Вынести bulk decrypt в isolate: `CryptoIsolateService.decryptBatch(List<Map> messages, SharedSecret secret)` → `List<Map>`
3. `MessageService.decryptAndSortMessages()` вызывает `decryptBatch()` — main isolate не блокируется
4. Одиночные encrypt/decrypt (sendMessage) остаются на main isolate — overhead isolate не оправдан для 1 операции

**Критерии:**
- Расшифровка 100 сообщений: UI плавный (60fps, 0 jank на timeline)
- Время расшифровки: ≤ +20% от синхронной (допустимый overhead)

**Тесты:**
- Unit test: `CryptoIsolateService.decryptBatch()` — корректный вывод
- Widget test: экран чата отзывчив во время расшифровки
- Нагрузочный: 500 сообщений — 0 jank на Flutter timeline

---

### Phase 3: GPU/шейдеры — снижение нагрузки на pipeline

**ВАЖНО:** Аудит выявил что основная GPU проблема — не фоновые эффекты, а chat bubble rendering. Каждый outgoing bubble в ListView содержит:
- `ScanlineOverlay` (320 drawLine на бабл)
- `BackdropFilter` × 3 (blur sigma 10-20)
При 10 видимых баблах = 3200 drawLine + 30 BackdropFilter на фрейм.

#### Task 6 — ScanlineOverlay: Picture cache для chat bubbles

**Файлы:**
- `client/lib/themes/apple_liquid/effects/scanline_overlay.dart`
- `client/lib/themes/apple_liquid/widgets/glass_chat_bubble.dart`

**Проблема:** ScanlineOverlay используется в `glass_chat_bubble.dart:118` — каждый outgoing bubble вызывает 320 `canvas.drawLine`. × ~10 видимых баблов = 3200 drawCall/фрейм.

**Решение:**
1. `_ScanlinePainter` — закешировать паттерн в `Picture` (paint once), переиспользовать через `Canvas.drawPicture()`.
2. `shouldRepaint` — если `intensity` не изменился, возвращать `Picture` из кэша.

**Критерии:**
- ScanlineOverlay на бабле: 1 `drawPicture` вместо 320 `drawLine`
- GPU: < 0.1ms на бабл

**Тесты:**
- Widget test: визуально идентично (golden)
- Performance test: compare drawLine count в timeline

---

#### Task 7 — BackdropFilter reduction на chat bubbles

**Файлы:**
- `client/lib/themes/apple_liquid/widgets/glass_chat_bubble.dart` (3 места: строка 60, 242, 274)
- `client/lib/themes/apple_liquid/effects/grain_overlay.dart` (опционально)
- `client/lib/themes/apple_liquid/effects/scanline_overlay.dart` (уже кэш из T6)

**Проблема:** 3 `BackdropFilter(blur: 10)` на каждый outgoing bubble × ~10 баблов = 30 слоёв blur на фрейм.

**Решение:**
1. Уменьшить blur sigma на chat bubbles с 10 до 6 (визуально почти неотличимо на цвете бабла)
2. Обернуть каждый bubble в `RepaintBoundary` (проверить — возможно уже есть)
3. GrainOverlay: не в ListView, только на registration_screen и empty_state — оставить как есть (уже RepaintBoundary)

**Критерии:**
- Chat bubble: ≤ 1 BackdropFilter на бабл (было 3)
- GPU: < 1ms суммарно на все баблы

**Тесты:**
- Golden test: blur sigma 6 vs 10 — визуально приемлемо
- Widget test: RepaintBoundary изолирует репаинт

---

#### Task 8 — ChromaticAberration: ghostBuilder на все платформы

**Файлы:**
- `client/lib/themes/apple_liquid/effects/chromatic_aberration.dart`
- `client/lib/themes/apple_liquid/widgets/glass_text_field.dart`

**Проблема:** cheap-ghost (`ghostBuilder`) существует (M10.1), но активирован только для `kIsWeb`. На мобиле `ghostBuilder = null` → 3× полный child (с BackdropFilter) на ~300ms при фокусе.

**Решение:**
1. Расширить `ghostBuilder` на мобильные платформы (убрать `kIsWeb ? ... : null` gate)
2. Заменить на `Platform.isAndroid || Platform.isIOS` или просто всегда cheap-ghost

**Критерии:**
- GlassTextField на мобиле: ChromaticAberration рендерит cheap Container вместо 3× child
- GPU timeline: 0 дополнительных слоёв в фазе анимации

---

### Phase 4: Архитектура/инфраструктура

---

#### Task 10 — LocalAppService singleton

**Файлы:** `client/lib/local_app_service.dart` (класс), **16 call sites** (main.dart, chats_screen, settings_screen, profile_screen, contacts_screen, call_manager, call_controllers, p2p_discovery_service, registration_screen, etc.)

**Проблема:** `LocalAppService()` — обычный public constructor, не singleton. Каждый из 16 вызовов создаёт новый инстанс. Конструктор (строка 27) выполняет:
- `_messages.attachGroupCrypto(...)` — перерегистрирует group crypto callback
- `unawaited(_kickoffBackgroundWorkers())` — запускает P2PService retry worker + attachment eviction **повторно**
- `Logger.info(...)` — лишние логи

**Решение:**
1. `static final LocalAppService _instance = LocalAppService._();` + `factory LocalAppService() => _instance;`
2. Перенести callback wire-up из конструктора в отдельный `init()` метод, вызываемый один раз из `main.dart`
3. `_kickoffBackgroundWorkers()` — должен быть guarded (сейчас не guarded в конструкторе)

**Критерии:**
- `identical(LocalAppService(), LocalAppService())` → `true`
- `_kickoffBackgroundWorkers()` выполняется ровно 1 раз за lifecycle приложения

**Тесты:**
- Unit test: identity check
- Unit test: `_kickoffBackgroundWorkers()` вызывается 1 раз (mock counter)

---

#### Task 11 — StreamController/dispose audit

**Файлы:** `client/lib/p2p_discovery_service.dart` (12-13 leak), `client/lib/p2p_service.dart` (87-88 leak), `client/lib/services/diagnostics/diagnostics_service.dart` (OK — есть dispose), все signaling сервисы (OK — есть close)

**Проблема:** Аудит показал:
- `P2PDiscoveryService._peerController` (строка 12-13) — `StreamController.broadcast()` **не закрывается** в `stop()` (строка 34-37)
- `P2PService._messageController` (строка 87-88) — leak: data channels закрываются, но сам StreamController не закрыт
- `DiagnosticsService._controller` (строка 51) — OK, dispose есть
- `WebRtcSignalingService`, `IncomingCallSignalingService`, `PresenceService` — OK, StreamController.close() присутствует

**Решение:**
1. `P2PDiscoveryService.stop()`: добавить `await _peerController.close()`
2. `P2PService`: добавить `dispose()` или `close()` для `_messageController`
3. `DiagnosticsService`: оставить как есть (уже корректно)

**Критерии:**
- Все `StreamController` в `lib/` имеют соответствующий `close()` в dispose/stop
- Memory leak test: создание/уничтожение 100 экземпляров → 0 рост

**Тесты:**
- Unit test: `P2PDiscoveryService.stop()` → `_peerController.isClosed` == true
- Unit test: `P2PService.dispose()` → `_messageController.isClosed` == true

---

### Phase 5: Startup — parallel init

#### Task 12 — Defer сетевых операций после первого фрейма

**Файлы:** `client/lib/main.dart`, `client/lib/local_app_service.dart`

**Проблема:** `startPBBasedWorkers()` (вызов на строке 87 main.dart) делает **6 I/O операций на критическом пути** до первого фрейма:

| Операция | Тип | Не нужна для первого фрейма? |
|---|---|---|
| `_publishOwnProfile()` | HTTP | Да |
| `_presence.start()` | HTTP + WS | Да |
| `_userDirectory.fetchAllProfiles()` | HTTP | Да |
| `syncToLocalContacts()` | Local I/O | Да (lazy-load) |
| `AppStatsPushService.pushStats()` | HTTP | Да |
| `DeviceRegistryService.init()` | Local I/O | **Спорно** (install_count) |

Пользователь видит `StealthLoadingIndicator` пока все эти операции завершатся (1-2 секунды).

**Решение:**
1. Перенести `startPBBasedWorkers()` и `DeviceRegistryService.init()` после первого frame через `WidgetsBinding.instance.addPostFrameCallback` или `unawaited(...)`.
2. На критическом пути оставить только:
   - `dotenv.load()` + `applyDartDefineOverrides()` (Level 0, параллельно)
   - `LocalAppService()` — создание фасада
   - `_checkRegistration()` — чтение userId из storage
3. `ThemeController.loadInitial()` — форматизировать: `await` в Level 0 (сейчас fire-and-forget).

**Критерии:**
- Cold start: первый фрейм (MainTabs/RegistrationScreen) < 200ms (сейчас ~1000-2000ms)
- Lazy-инициализация: все deferred операции завершаются до того как пользователь может с ними взаимодействовать

**Тесты:**
- Integration test: `runApp` → первый фрейм ≤ 200ms
- Unit test: init graph — порядок сохранён

---

### Phase 6: Low priority / Future-proofing / Refinement

Задачи с низким приоритетом — не влияют на текущую производительность, но улучшают архитектуру или готовят почву под будущие изменения.

#### Task 9 — PresenceService heartbeat: событийная модель (optional)
*(перемещён из Phase 4 — timer lifecycle БЕЗ БАГОВ, не критично)*

**Файл:** `client/lib/services/user_directory/presence_service.dart`

**Контекст:** Аудит показал что timer lifecycle идеально чист: `startHeartbeat()` идемпотентен, `dispose()` выставляет `_disposed` до cancel, все callback'и проверяют `_disposed`. 30s heartbeat — валидный паттерн.

**Решение (опционально):** Заменить 30s heartbeat на событийную модель — `lastSeen` только при foreground / sendMessage.

**Критерии:**
- `PresenceService`: 0 `Timer.periodic`

---

#### Task 2b — ChatListPanel: resolve 7 blockers (future)
*(выделен из T2 — swap не тривиален)*

**Файлы:** `client/lib/ui/screens/chats/chat_list_panel.dart`, `client/lib/ui/screens/chats_screen.dart`

**7 blocker-ов:**
1. `onSelectChat` — type mismatch (`void` vs `Future<void>`)
2. Missing `onSearchChanged` handler с debounce
3. Missing `initials` function
4. Loading indicator: `StealthSkeletonList` (inline) vs `CircularProgressIndicator` (extracted)
5. `_ChatTile` — hardcoded стили, не использует тему
6. Unread badge: `statusWarn` vs `systemOrange`
7. Missing `AccessibilityIds.chatTileAvatar`

**Решение:** Когда будет время — решить blockers 1-7 и заменить inline `_buildChatListPanel`.

---

#### Task (old) T6 — CircuitBoardBackground: кеширование canvas
*(перемещён из Phase 3 — используется только на loading screen ~2 секунды)*

**Файл:** `client/lib/themes/apple_liquid/widgets/circuit_board_background.dart`

**Решение:** `RepaintBoundary` + Picture cache. Анимация 30s repeat — но живёт ~2s до dispose.

---

#### Task 13 — DecryptText: AnimatedBuilder readiness

**Файл:** `client/lib/themes/apple_liquid/motion/decrypt_text.dart`

**Контекст:** Единственное использование — loading screen, 400ms, 7 символов. Per-frame `setState` (24 фрейма) не создаёт проблем.

**Решение:** `AnimatedBuilder` — future-proofing.

---

#### Task 14 — Добавить benchmark gates + perf docs

**Файлы:** `client/test/performance/`, `docs/PERFORMANCE.md`

**Решение:**
1. `rebuild_count_test.dart` — Flutter benchmark:
   - `chats_screen.dart` rebuild count при поиске
   - `chat_screen.dart` rebuild count при скролле
2. `startup_time_test.dart` — измерить init время, baseline
3. `gpu_timeline_test.dart` — замерить drawLine count / BackdropFilter count
4. **Создать `docs/PERFORMANCE.md`** — таблица baselines → results по каждому task (checkpoint производительности)

---

## Commit Plan

| # | Коммит | Tasks | Сообщение |
|---|---|---|---|
| 1 | Quick wins UI | T1, T2 (InsightPanel + search bar) | `perf(ui): search caching + debounce, InsightPanel swap` |
| 2 | Data layer | T3, T4, T5 | `perf(data): pagination, N+1 batch resolve, crypto isolate` |
| 3 | GPU/shaders | T6, T7, T8 | `perf(gpu): ScanlineOverlay cache, BackdropFilter reduction, ChromaticAberration ghost` |
| 4 | Architecture | T10, T11 | `perf(arch): singleton, StreamController close` |
| 5 | Startup | T12 | `perf(startup): defer network ops after first frame` |
| 6 | Low priority | T9, T13, T14, T2b, old-T6 | `perf(misc): presence optional, DecryptText, benchmarks, CircuitBoard, ChatListPanel` |

**Cross-commit dependencies:**
- Commit 2 data layer: T3 (pagination) → T4 (N+1) — T3 переписывает `fetchLastMessage` и `getMessages`. T5 (crypto isolate) — независим.
- Commit 4 (architecture): T10/T11 независимы.
- Commit 6 (low priority): независим от всех, может быть в конце или пропущен.
