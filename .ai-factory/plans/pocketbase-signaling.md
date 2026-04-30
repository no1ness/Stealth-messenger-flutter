# План: PocketBase сигналинг для WebRTC звонков

**Ветка:** `feature/pocketbase-signaling` (создаётся вручную после коммита/стэша текущих WIP-изменений — см. `Pre-flight` ниже)
**База:** `main`
**Создан:** 2026-04-29
**Уточнён:** 2026-04-29 (после `/aif-improve`)
**Slug:** `pocketbase-signaling`

## Settings

- **Testing:** Yes — unit-тесты для `WebRtcSignalingService` + smoke-тест с реальным PocketBase (по образцу `message_flow_smoke_test.dart`)
- **Logging:** Verbose — детальные DEBUG-логи через `debugPrint` с тегом `[stealth-call]` и подтегом транспорта (`[signaling]`)
- **Docs:** Yes — обязательный docs checkpoint (обновить `DESCRIPTION.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, добавить `docs/POCKETBASE_SETUP.md`)
- **Roadmap Linkage:** Milestone: "none" — Rationale: ROADMAP.md в проекте отсутствует, привязка пропущена.

## Цель

Заменить Supabase Realtime broadcast на PocketBase Realtime (SSE + database-source) как канал сигналинга WebRTC звонков. Решает три текущих проблемы:

1. **Доставка не гарантирована** в Supabase broadcast: события `call_initiation` и `call_accept` теряются (см. `CALL_BUG_ANALYSIS.md`).
2. **ТСПУ-блокировки в РФ:** Supabase Realtime использует WSS на нестандартных портах; легко блокируется. PocketBase = собственный домен + TURNS:443 = маскируется под обычный HTTPS.
3. **Vendor lock-in:** Supabase отключаем из call-пути целиком; в долгосрочной перспективе всё, что не относится к звонкам (контакты, история), тоже мигрирует на PocketBase, но это вне скоупа этого плана.

После плана звонки идут через **PocketBase only** на ОБЕИХ платформах — native (Android/iOS) и web. Supabase в call-пути не вызывается.

## Архитектура целевого решения

```
   Caller (Flutter)                                Callee (Flutter)
        |                                                |
        | startCall(roomId, targetUserId)                |
        |                                                |
        v                                                v
  [WebRtcSignalingService]<--SSE subscribe-->[PocketBase Realtime]
        |          |        ^                            |
        |          | filter |                            |
        |          v target |                            |
        |      pb.collection('rtc_signaling').create()   |
        |                                                |
        |---- offer (filtered to callee) ----------------|
        |<---- answer (filtered to caller) --------------|
        |---- ICE candidates (both directions) ----------|
        |---- hangup (graceful close) -------------------|
        |                                                |
        +---WebRTC media (P2P/TURNS:443) ----------------+

   ┌─────────────────────┐
   │  PocketBase server  │  <-- single Go binary, SQLite
   │  collections:       │      hosting: VPS или MikroTik container
   │   - users           │      настраивается отдельной задачей
   │   - rtc_signaling   │
   │  (TLS:443)          │
   └─────────────────────┘
```

**Ключевые отличия от текущей Supabase-архитектуры:**

- Один канал вместо двух (`rtc_signaling` коллекция вместо `user_calls:*` + `chat_calls:*`).
- Гарантированная доставка: записи в БД, не broadcast (можно посмотреть историю, не теряются если callee офлайн в момент звонка).
- Сам `offer` сигнализирует о входящем звонке — не нужен отдельный `call_initiation`. См. `CALL_BUG_ANALYSIS.md` Вариант 2.
- Фильтрация на стороне сервера через PocketBase API rules + клиентский subscribe-фильтр `target = currentUserId`.
- TURNS на порту 443 для обхода ТСПУ — конфигурируется через `.env`.
- Reconnect-логика для SSE с экспоненциальным backoff — закладывается с самого начала.

## Pre-flight (выполнить до создания ветки)

В рабочем дереве сейчас есть незакоммиченный WIP с прошлой сессии:

```
M  client/lib/supabase_service.dart                            <- конфликтует с этим планом
M  client/lib/ui/screens/webrtc_call_screen_native_impl.dart   <- конфликтует с этим планом
M  client/lib/ui/widgets/call_manager.dart                     <- конфликтует с этим планом
M  pw-test/appium-simple-call-test.mjs                         <- безопасно нести в новую ветку
M  pw-test/debug-emulator-source.xml                           <- мусор, можно стереть
?? CALL_BUG_ANALYSIS.md                                        <- контекст, оставить
?? pw-test/appium-phone-dump.mjs                               <- helper, можно нести
?? pw-test/phone-dump-source.xml                               <- мусор, удалить
?? pw-test/test-call-with-logs.mjs                             <- helper, можно нести
```

**Рекомендация перед стартом /aif-implement:**

1. Закоммитить текущий WIP-фикс одним коммитом на `main`:
   ```
   git add client/lib/ui/screens/webrtc_call_screen_native_impl.dart \
           client/lib/ui/widgets/call_manager.dart \
           client/lib/supabase_service.dart \
           pw-test/appium-simple-call-test.mjs \
           pw-test/appium-phone-dump.mjs \
           pw-test/test-call-with-logs.mjs \
           CALL_BUG_ANALYSIS.md
   git commit -m "wip: audio routing fix + call_manager logging + appium debug helpers"
   ```
2. Стереть мусорные дампы: `git checkout -- pw-test/*.xml && rm -f pw-test/phone-dump-source.xml` (опционально).
3. Создать ветку: `git checkout -b feature/pocketbase-signaling`.

## Research Context

См. `CALL_BUG_ANALYSIS.md` (корневые причины текущих обрывов сигналинга). Дополнительно (после `/aif-improve`):

- Web-имплементация (`webrtc_call_screen_web.dart`, 1051 строка) использует **те же** методы Supabase, что и native — `subscribeCalls`, `sendOffer`, `sendAnswer`, `sendIceCandidate`, `sendCallAccept`, `sendCallEnd`. Удаление этих методов **сломает web-сборку**, поэтому миграция web входит в скоуп этого плана.
- В проекте **нет** `mockito`/`mocktail` и нет `integration_test/` — стиль тестов: manual fakes (`class _FakeX implements X`) + один smoke-тест с реальной БД (`message_flow_smoke_test.dart`). Тесты в этом плане следуют тому же стилю.
- `LocalDatabaseService.getChatById(chatId)` уже возвращает chat с массивом `members[]` — `PeerResolver` можно сделать **local-only**, без Supabase fallback.
- Текущий код **не обрабатывает** разрыв signaling-WS в принципе. Это отдельный пробел, закрываемый задачей 9 (reconnect).

## Tasks

### Фаза 1: Фундамент (зависимости, модели, интерфейс)

#### 1. Добавить SDK PocketBase в Flutter-клиент `[DONE]`

- **Файл:** `client/pubspec.yaml`
- **Действие:** Добавить `pocketbase: ^0.18.0` (или последняя стабильная) в раздел `dependencies`. Запустить `flutter pub get`. Зафиксировать `pubspec.lock`.
- **Логирование:** не требуется (build-time изменение).

#### 2. Создать структуру каталогов signaling `[DONE]`

- **Каталоги:**
  - `client/lib/services/signaling/`
  - `client/test/services/signaling/`
- **Действие:** Создать пустые директории-плейсхолдеры с `.gitkeep`, далее задачи положат туда файлы.

#### 3. Создать модель `RtcMessage` `[DONE]`

- **Файл:** `client/lib/services/signaling/rtc_message.dart`
- **Содержимое:** Dart-класс, маппинг на PocketBase коллекцию `rtc_signaling`.
  - Поля: `id` (String), `roomId` (String), `creator` (String, userId), `target` (String, userId), `type` (enum `RtcMessageType { offer, answer, candidate, hangup }`), `payload` (`Map<String, dynamic>`), `created` (DateTime).
  - `RtcMessage.fromRecord(RecordModel record)` — десериализация из PocketBase RecordModel.
  - `Map<String, dynamic> toCreateBody()` — сериализация для `pb.collection().create()`.
  - `RtcMessageType` enum с `fromString()` для разбора и обработкой неизвестных значений (`throwOnUnknown` или `unknown` вариант — выбрать в имплементации).
- **Логирование:** при `fromRecord` логировать `[signaling] RtcMessage parsed type=$type roomId=$roomId from=$creator to=$target`.

#### 4. Создать абстрактный интерфейс `SignalingTransport` `[DONE]`

- **Файл:** `client/lib/services/signaling/signaling_transport.dart`
- **Содержимое:** abstract class с методами:
  - `Future<void> connect({required String roomId, required String selfUserId})`
  - `Future<void> sendOffer({required String roomId, required String targetUserId, required Map<String, dynamic> sdp})`
  - `Future<void> sendAnswer({required String roomId, required String targetUserId, required Map<String, dynamic> sdp})`
  - `Future<void> sendCandidate({required String roomId, required String targetUserId, required Map<String, dynamic> candidate})`
  - `Future<void> sendHangup({required String roomId, required String targetUserId})`
  - `Stream<RtcMessage> get incoming` — поток входящих сообщений (offer/answer/candidate/hangup, отфильтрованных по target=self).
  - `Stream<SignalingConnectionState> get connectionState` — состояние транспорта (`connected | reconnecting | disconnected | error`).
  - `Future<void> disconnect()`
- **Цель:** позволяет в будущем swap-нуть PocketBase на другой бэкенд без изменений в WebRTC-слое.
- **Логирование:** не требуется в интерфейсе (только в имплементации).

#### 5. Расширить TURN-конфигурацию для TURNS:443 `[DONE]`

- **Файл:** `client/lib/ui/screens/webrtc_call_screen_native_impl.dart` — функция `_buildIceServers()` (строки 154–184).
- **Действие:**
  - Прочитать также `dotenv.env['TURNS_URL']` (отдельная переменная для TLS-варианта на порту 443).
  - Если `TURNS_URL` задан — добавить отдельным `iceServer` поверх обычного TURN. Пример:
    ```
    {
      'urls': ['turns:my-domain.com:443?transport=tcp'],
      'username': '...',
      'credential': '...',
    }
    ```
  - Если есть только `TURN_URL` — оставить текущее поведение.
- **Файл:** `client/lib/ui/screens/webrtc_call_screen_web.dart` — аналогичная функция построения ICE servers (найти при имплементации). Применить ту же логику чтения `TURNS_URL`.
- **Файл:** `client/.env.example`
- **Действие:** Добавить заглушки `TURNS_URL=turns:CHANGE_ME.example:443?transport=tcp`, `TURNS_USERNAME=`, `TURNS_PASSWORD=` с комментарием про ТСПУ.
- **Логирование:** `debugPrint('[stealth-call] TURNS configured: $turnsUrls')` или WARN, если TURNS не задан.

**▼ Commit checkpoint #1:** `feat(signaling): add pocketbase SDK, RtcMessage model, SignalingTransport interface, TURNS:443 config`

---

### Фаза 2: PocketBase имплементация

#### 6. Реализовать `WebRtcSignalingService` (PocketBase backend) `[DONE]`

- **Файл:** `client/lib/services/signaling/webrtc_signaling_service.dart`
- **Класс:** `WebRtcSignalingService implements SignalingTransport`
- **Зависимости:** `PocketBase` инстанс (URL из `dotenv.env['POCKETBASE_URL']`), текущий `selfUserId`.
- **Поведение:**
  - **Аутентификация:** lazy `pb.collection('users').authWithPassword(...)` ИЛИ `pb.authStore.save(token, model)` если auth уже сделан в registration flow. Решить как: см. задачу 7.
  - **`connect(roomId, selfUserId)`:** сохраняет состояние, подписывается через `pb.collection('rtc_signaling').subscribe('*', _onRecord, filter: "roomId='$roomId' && target='$selfUserId'")`. Сохраняет `unsubscribe`-функцию.
  - **`_onRecord(RecordModel)`:** парсит в `RtcMessage`, делает `_incomingController.add(msg)`.
  - **`sendOffer/Answer/Candidate/Hangup`:** `await pb.collection('rtc_signaling').create({roomId, creator: selfUserId, target: targetUserId, type, payload})`. Возвращает Future<void>; ошибки прокидывает наружу.
  - **`incoming`:** `Stream<RtcMessage>` из broadcast `StreamController`.
  - **`connectionState`:** `Stream<SignalingConnectionState>` — заглушка-`connected` на этом этапе; реальная логика добавляется в задаче 9.
  - **`disconnect()`:** unsubscribe + `_incomingController.close()`.
- **Логирование:**
  - `[signaling] connect roomId=$roomId selfUserId=$selfUserId`
  - `[signaling] subscribed filter='$filter'`
  - `[signaling] send type=$type room=$roomId to=$targetUserId payloadSize=$bytes`
  - `[signaling] recv type=$type room=$roomId from=$creator`
  - `[signaling] send error: $error` (на любом catch)
  - `[signaling] disconnect roomId=$roomId`

#### 7. Аутентификация PocketBase: lazy через secure storage `[DONE]`

- **Файл:** `client/lib/services/signaling/webrtc_signaling_service.dart` (метод `_ensurePocketBaseAuth()`)
- **Решение:**
  - Если в `flutter_secure_storage_x` уже есть `pb_token` — восстановить через `pb.authStore.save(token, model)`.
  - Если нет — `pb.collection('users').create({email, password, passwordConfirm, name})` (генерируем технический email вида `<userUUID>@stealth.local` и случайный пароль), сохраняем токен в secure storage.
  - Этот метод вызывается лениво при первом `connect()`.
- **Файл:** `client/lib/registration_screen.dart` — НЕ меняем; auth для PocketBase делается лениво в сервисе. (Регистрация на Supabase остаётся для контактов.)
- **Логирование:** `[signaling] auth restored from storage` / `[signaling] auth created new user pbId=$id`.

#### 8. PocketBase singleton client `[DONE]`

- **Файл:** `client/lib/services/signaling/pocketbase_client.dart`
- **Содержимое:** `PocketBaseClient.instance` — lazy singleton, читает URL из `dotenv.env['POCKETBASE_URL']`, выкидывает `StateError`, если URL не задан.
- **Логирование:** при инициализации `[signaling] PocketBase client init url=$url`.

#### 9. Reconnect / WS error handling в `WebRtcSignalingService` `[DONE]`

- **Файл:** `client/lib/services/signaling/webrtc_signaling_service.dart`
- **Цель:** PocketBase SDK имеет встроенный auto-reconnect для SSE, но клиент должен:
  - Слушать `connectivity_plus` для переключения сетей (Wi-Fi ↔ LTE) и форсировать ресубскрайб.
  - Эмитить состояния через `connectionState` stream: `connected | reconnecting | disconnected | error`.
  - При обрыве — экспоненциальный backoff (1s, 2s, 4s, 8s, max 30s) для пересоздания подписки.
  - При успешном reconnect — повторно вызвать `subscribe()` с тем же фильтром.
- **Действие:**
  - Добавить `enum SignalingConnectionState { connected, reconnecting, disconnected, error }` в `signaling_transport.dart`.
  - В `WebRtcSignalingService` подписаться на `Connectivity().onConnectivityChanged`.
  - Реализовать retry-цикл с backoff.
- **Логирование:** `[signaling] connection state=$state attempt=$n nextDelay=$ms`.
- **Тест:** unit-тест задачей 18 проверяет переходы состояний на mock-разрывах.

**▼ Commit checkpoint #2:** `feat(signaling): WebRtcSignalingService PocketBase implementation + lazy auth + reconnect`

---

### Фаза 3: Интеграция в WebRTC-слой и удаление Supabase из call-пути

#### 10. Создать `IncomingCallSignalingService` для глобальной подписки на входящие звонки `[DONE]`

- **Файл:** `client/lib/services/signaling/incoming_call_service.dart`
- **Цель:** заменить `SupabaseService.subscribeToUserCalls()` (используется в `CallManager`) на PocketBase-эквивалент.
- **Поведение:**
  - Подписка на коллекцию `rtc_signaling` с фильтром `target='$selfUserId' && type='offer'`. То есть приём `offer` напрямую = это и есть «входящий звонок».
  - Извлекаем `roomId` (= chatId), `creator` (= fromUserId), `payload['nickname']` (если положен в payload), сам `payload['sdp']` (offer SDP).
  - Эмитит `Stream<IncomingCall>` где `class IncomingCall { String roomId; String fromUserId; String fromNickname; bool isVideoCall; RTCSessionDescription offerSdp; }` — содержит **уже принятый offer**.
- **Передача offer в `WebRTCCallScreen`:** добавить опциональные параметры `RTCSessionDescription? initialOffer` и `String? callerUserId` в конструктор `WebRTCCallScreen`. Когда callee нажимает Answer, `CallManager` пушит экран с этими параметрами. В `_startCall()` экран не подписывается на ожидание offer — он сразу делает `setRemoteDescription(initialOffer)` → `createAnswer()` → `sendAnswer()`. Это убирает race condition «callee подписался слишком поздно».
- **Решение по протоколу:** `call_initiation` не нужен как отдельное событие — сам `offer` сигнализирует о входящем. Это существенно упрощает архитектуру (см. CALL_BUG_ANALYSIS.md, Вариант 2).
- **Логирование:** `[signaling] incoming offer detected roomId=$roomId from=$creator`.

#### 11. Перевести `CallManager` на новый `IncomingCallSignalingService` `[DONE]`

- **Файл:** `client/lib/ui/widgets/call_manager.dart`
- **Действие:**
  - Удалить импорт `supabase_service.dart` для call-частей; заменить на `incoming_call_service.dart`.
  - В `_initGlobalCallListener()` подписаться на `incomingCallStream` нового сервиса вместо `subscribeToUserCalls`.
  - `_handleCallInitiation` переименовать в `_handleIncomingOffer`. Получает `IncomingCall` (с offer SDP внутри), показывает диалог. При нажатии Answer — пушит `WebRTCCallScreen(initialOffer: incomingCall.offerSdp, callerUserId: incomingCall.fromUserId, ...)`.
  - Убрать вызов `_supabaseService.recordIncomingCall()`, `markIncomingCallDeclined()`, `sendCallEnd()` — заменить на эквиваленты через локальную БД (история звонков пишется в `LocalDatabaseService`) ИЛИ оставить вызов Supabase для истории, но НЕ для сигналинга. Решение: history-методы в `SupabaseService` остаются (см. задачу 16); удаляются только сигналинг-методы.
  - При Decline — отправить `signalingService.sendHangup(roomId, fromUserId)`.
- **Логирование:** сохранить все существующие логи `[stealth-call] CallManager …`, переключить на новый сервис.

#### 12. Перевести `WebRTCCallScreen` (native: `webrtc_call_screen_native_impl.dart`) на `SignalingTransport` `[DONE]`

- **Файл:** `client/lib/ui/screens/webrtc_call_screen_native_impl.dart`
- **Действие:**
  - Конструктор: добавить `RTCSessionDescription? initialOffer`, `String? callerUserId` (см. задачу 10).
  - Поле `_signaling = WebRtcSignalingService(...)` вместо `_supabaseService` для всех call-операций.
  - `_supabaseService.subscribeCalls` (строка 104) → `_signaling.connect(roomId: chatId, selfUserId: ...)` + listen на `_signaling.incoming`.
  - В listen — switch по `RtcMessageType`: offer → `_handleOffer`, answer → `_handleAnswer`, candidate → `_handleRemoteCandidate`, hangup → `_handleRemoteHangup` (новый, см. задачу 13).
  - Если `widget.initialOffer != null` (callee пришёл с уже принятым offer) — сразу применить через `_handleOffer({'offer': offerMap, 'from_user_id': widget.callerUserId})`, минуя поток подписки.
  - `_supabaseService.sendOffer` (331) → `_signaling.sendOffer(roomId, targetUserId, sdp)`. Получить `targetUserId` через `PeerResolver` (см. задачу 15).
  - `_supabaseService.sendAnswer` (365) → `_signaling.sendAnswer(...)` (target = `widget.callerUserId` для callee).
  - `_supabaseService.sendIceCandidate` (225) → `_signaling.sendCandidate(...)`.
  - Убрать `_supabaseService.sendCallAccept` (строка 135) и обработку `callAcceptedStream` (124–128). Логика «caller ждёт accept перед отправкой offer» больше не нужна: caller сразу шлёт offer; callee получает его через `IncomingCallSignalingService` ДО открытия экрана.
  - `_supabaseService.sendCallEnd` (570) → `_signaling.sendHangup(roomId, targetUserId)` + `_signaling.disconnect()`.
  - **НЕ менять** существующие callbacks (`onIceConnectionState`, `onTrack`, аудио-роутинг), стэтс-логгер, audio routing fix, permission flow — они остаются 1:1.
- **Логирование:** сохранить все `[stealth-call]` логи; добавить `[stealth-call] using signaling=PocketBase`.

#### 13. Hangup signal end-to-end `[DONE]`

- **Цель:** заменить текущую цепочку `_hangUp() → sendCallEnd() → CallManager._handleCallEnded() → markCurrentUserCallEnded() + Navigator.pop()` на эквивалент через PocketBase.
- **Файлы:**
  - `client/lib/ui/screens/webrtc_call_screen_native_impl.dart` — `_hangUp()` теперь шлёт `_signaling.sendHangup(...)` (см. задачу 12).
  - `client/lib/services/signaling/incoming_call_service.dart` — расширить подписку: фильтр `target='$selfUserId' && (type='offer' || type='hangup')`. Эмитить второй стрим `Stream<HangupSignal>` (или enrich-ить `IncomingCall` событие типом).
  - `client/lib/ui/widgets/call_manager.dart` — слушать поток hangup, при получении вызывать `Navigator.popUntil` для активного call screen + опционально снэк-бар «Call ended by peer».
  - `client/lib/ui/screens/webrtc_call_screen_native_impl.dart` — добавить метод `_handleRemoteHangup(RtcMessage)`: останавливает stats logger, вызывает `_disposeMedia`, `Navigator.pop`.
- **Логирование:** `[signaling] hangup received from=$creator roomId=$roomId` / `[stealth-call] remote hangup → closing screen`.

#### 14. Перевести `WebRTCCallScreen` (web: `webrtc_call_screen_web.dart`) на `SignalingTransport` `[DONE]`

- **Файл:** `client/lib/ui/screens/webrtc_call_screen_web.dart` (1051 строка)
- **Действие:** **те же изменения, что в задаче 12**, но для web-имплементации:
  - Конструктор: добавить `initialOffer`, `callerUserId`.
  - Заменить ВСЕ вызовы Supabase signaling на `SignalingTransport`:
    - line 134 (`subscribeCalls`) → `_signaling.connect()` + listen на `incoming`
    - line 161 (`sendCallAccept`) → удалить
    - line 256 (`sendIceCandidate`) → `_signaling.sendCandidate()`
    - line 395 (`sendOffer`) → `_signaling.sendOffer()`
    - line 457 (`sendAnswer`) → `_signaling.sendAnswer()`
    - line 677 (`sendCallEnd`) → `_signaling.sendHangup()` + `disconnect()`
  - Аналогичный hangup-handler как в native (задача 13).
  - `WebRtcSignalingService` должен работать одинаково на web и native (PocketBase Dart SDK кросс-платформенный — проверить в задаче 1).
- **Логирование:** те же теги `[stealth-call]` `[signaling]`.
- **Тест:** добавить пункт в Definition of Done — `flutter build web` собирается без ошибок.

#### 15. `PeerResolver` — local-only `[DONE]`

- **Файл:** `client/lib/services/signaling/peer_resolver.dart`
- **Цель:** резолвить `targetUserId` по `chatId` БЕЗ обращения к Supabase.
- **Решение:** использовать `LocalDatabaseService.getChatById(chatId)` — возвращает chat-объект с массивом `members[]`. Берём member ≠ `selfUserId`.
- **Реализация:** один метод `Future<String?> resolveTarget(String chatId, String selfUserId)`. Если chat не закэширован (первый запуск, нет связи) — выкидывает `PeerResolutionException` с понятным сообщением; UI должен ловить и показывать «Cannot start call: contact not synced yet».
- **Никаких Supabase fallbacks** — это последняя точка Supabase в call-пути, её надо изолировать в локальном пути.
- **Логирование:** `[signaling] resolved target for chatId=$id → $targetUserId`.

#### 16. Удалить call-related методы из `SupabaseService` `[DONE]`

- **Файл:** `client/lib/supabase_service.dart`
- **Удалить (строки указаны примерно):**
  - `subscribeToUserCalls` (1636), `unsubscribeUserCalls`
  - `sendCallInitiation` (1816), `sendCallAccept` (1854)
  - `sendOffer` (1958), `sendAnswer` (1970), `sendIceCandidate` (1982)
  - `subscribeCalls` (1684) и его helpers
  - `_callAcceptedController` (24), `callAcceptedStream` (26).
  - `sendCallEnd` (1950)
- **Сохранить:**
  - `recordIncomingCall`, `markIncomingCallDeclined`, `markCurrentUserCallEnded` — это история звонков (вызывается из `CallManager` для UI/истории, не для сигналинга).
  - `subscribeP2PSignaling` (1720) — используется для **P2P data channel сообщений**, не для звонков (см. `p2p_service.dart`). НЕ удалять.
  - `_getOtherUserId` — больше не нужен в call-пути; можно удалить если не используется в других местах (проверить grep при имплементации).
- **Зависимости:** эта задача **должна** идти ПОСЛЕ задач 12 и 14 (native + web уже мигрированы). Иначе сборка ломается.
- **Логирование:** не требуется (удаление кода).

**▼ Commit checkpoint #3:** `refactor(signaling): switch call signaling from Supabase to PocketBase on native+web, remove call-path Supabase methods`

---

### Фаза 4: Тесты

#### 17. Unit-тест для `RtcMessage` (сериализация/десериализация) `[DONE]`

- **Файл:** `client/test/services/signaling/rtc_message_test.dart`
- **Покрытие:**
  - `fromRecord` корректно парсит `RecordModel` с заданными полями.
  - `toCreateBody` возвращает Map с правильными ключами.
  - `RtcMessageType.fromString` парсит `offer`/`answer`/`candidate`/`hangup`, выкидывает на неизвестных.
- **Стиль:** обычный `flutter_test` без mock-фреймворков, чистая проверка функций.

#### 18. Unit-тест для `WebRtcSignalingService` (manual-fake style) `[DONE]`

- **Файл:** `client/test/services/signaling/webrtc_signaling_service_test.dart`
- **Стиль:** **manual fake** в духе существующих тестов (`_FakeContactsDataSource implements ContactsDataSource` в `contacts_screen_semantics_test.dart`). НЕ добавлять `mockito`/`mocktail` — соответствуем стилю проекта.
- **Покрытие:**
  - Создаём `class _FakePocketBase implements PocketBase` (или partial — только `collection`).
  - `sendOffer` вызывает `pb.collection('rtc_signaling').create()` с правильным телом — fake-метод запоминает `lastCreateBody`.
  - `incoming` стрим эмитит `RtcMessage`, когда fake вызывает зарегистрированный `_onRecord` callback.
  - `disconnect` отписывается и закрывает контроллер.
  - `connectionState` транзишит через `connected → reconnecting → connected` при синтетическом disconnect-событии.
- **Логирование:** verbose в тесте через `debugPrint` (для дебага flaky тестов).

#### 19. Smoke-тест end-to-end сигналинга через реальный PocketBase `[DONE]`

- **Файл:** `client/test/services/signaling/pocketbase_signaling_smoke_test.dart`
- **Стиль:** **по образцу `client/test/message_flow_smoke_test.dart`** (использует реальный backend, читает URL из env, skip при отсутствии).
- **Подход:**
  - Перед запуском требует `POCKETBASE_TEST_URL` в env (например, `localhost:8090`); иначе `markTestSkipped`.
  - Создаются два инстанса `WebRtcSignalingService` с разными userId.
  - Один шлёт offer → второй принимает через подписку → шлёт answer → первый принимает.
  - Проверяется hangup-цепочка: один шлёт hangup → второй получает в `incoming`.
- **Не использует** `integration_test/` пакет (его нет в проекте) — обычный `flutter test`.
- **Логирование:** verbose.

**▼ Commit checkpoint #4:** `test(signaling): unit tests + smoke test for PocketBase signaling`

---

### Фаза 5: Конфигурация, документация, очистка

#### 20. Обновить `.env.example` и валидировать `POCKETBASE_URL` при старте `[DONE]`

- **Файл:** `client/.env.example`
- **Добавить:**
  ```
  # PocketBase signaling backend (REQUIRED for calls)
  POCKETBASE_URL=https://signal.example.com
  # Поднимается отдельно (Docker/MikroTik/VPS) — см. docs/POCKETBASE_SETUP.md

  # TURNS на 443 для обхода ТСПУ (РФ)
  TURNS_URL=turns:turn.example.com:443?transport=tcp
  TURNS_USERNAME=
  TURNS_PASSWORD=
  ```
- **Файл:** `client/lib/main.dart`
- **Действие:** в `main()` после загрузки `.env` валидировать `POCKETBASE_URL`; если пуст — показывать `StartupErrorScreen` с инструкцией. Не падать молча.
- **Логирование:** `[stealth-call] PocketBase URL: $url` (без secrets).

#### 21. Создать `docs/POCKETBASE_SETUP.md` `[DONE]`

- **Файл:** `docs/POCKETBASE_SETUP.md`
- **Содержимое:**
  - Минимальный docker-compose для PocketBase + caddy для TLS:
    ```yaml
    services:
      pocketbase:
        image: ghcr.io/muchobien/pocketbase:latest
        volumes: [./pb_data:/pb_data]
        ports: ["8090:8090"]
    ```
  - Схема коллекции `rtc_signaling`:
    | Field    | Type   | Required | Notes |
    |----------|--------|----------|-------|
    | roomId   | text   | yes      | indexed |
    | creator  | rel(users) | yes  | |
    | target   | rel(users) | yes  | indexed |
    | type     | select | yes      | values: offer, answer, candidate, hangup |
    | payload  | json   | yes      | sdp / candidate object |
  - API rules:
    - `listRule` / `viewRule`: `target.id = @request.auth.id` (юзер видит только сообщения, адресованные ему)
    - `createRule`: `creator.id = @request.auth.id` (юзер может создавать только от своего имени)
    - `updateRule`: `null` (никто не редактирует)
    - `deleteRule`: `creator.id = @request.auth.id` (только автор)
  - Cleanup: cron-хук в PocketBase (`onRecordsAfterCreateRequest` или scheduled job) для удаления записей старше 1 часа — иначе коллекция растёт без лимита.
  - Раздел про деплой на MikroTik (контейнер) и про настройку Let's Encrypt через Caddy.
  - Раздел про создание схемы — admin UI или migration JSON.

#### 22. Обновить `.ai-factory/DESCRIPTION.md` и `docs/` `[DONE]`

- **`.ai-factory/DESCRIPTION.md`:**
  - В разделе «Технологический стек»: добавить `pocketbase: ^0.18.x` и заменить «Supabase Realtime» на «PocketBase Realtime (SSE)» в описании сигналинга.
  - В разделе «Архитектурные решения»: обновить пункт про Direct P2P First — «сигналинг = PocketBase, медиа = WebRTC P2P».
  - В «Точки входа»: добавить `client/lib/services/signaling/webrtc_signaling_service.dart`.
- **`docs/ARCHITECTURE.md`:** добавить диаграмму потока сигналинга через PocketBase + описание коллекции `rtc_signaling`.
- **`docs/SECURITY.md`:** добавить параграф про PocketBase auth (token в secure storage), API rules, и почему PocketBase сам по себе НЕ E2E (но payload offer/answer/ICE не содержит секретов — содержит SDP, который и так передаётся в открытую в WebRTC).

#### 23. Обновить Settings-экран (минимально) `[DONE]`

- **Файл:** `client/lib/ui/screens/settings_screen.dart`
- **Действие:** Добавить read-only строку «Signal server: $pocketbaseUrl» в раздел сетевых настроек. Override в runtime НЕ делаем (out of scope, только из `.env` на этом этапе).
- **Логирование:** не требуется.
- **NB:** UI правки минимальные, в основном — отображение текущего URL из `dotenv.env`.

**▼ Commit checkpoint #5 (final):** `docs(signaling): PocketBase setup guide, updated DESCRIPTION/ARCHITECTURE/SECURITY, .env.example`

---

## Commit Plan (итог)

| # | Чекпойнт | Задачи | Сообщение |
|---|----------|--------|-----------|
| 1 | После задач 1–5 | Фундамент | `feat(signaling): add pocketbase SDK, RtcMessage model, SignalingTransport interface, TURNS:443 config` |
| 2 | После задач 6–9 | PocketBase impl + reconnect | `feat(signaling): WebRtcSignalingService PocketBase implementation + lazy auth + reconnect` |
| 3 | После задач 10–16 | Интеграция (native + web) + удаление Supabase | `refactor(signaling): switch call signaling from Supabase to PocketBase on native+web, remove call-path Supabase methods` |
| 4 | После задач 17–19 | Тесты | `test(signaling): unit tests + smoke test for PocketBase signaling` |
| 5 | После задач 20–23 | Конфиг + docs | `docs(signaling): PocketBase setup guide, updated DESCRIPTION/ARCHITECTURE/SECURITY, .env.example` |

## Out of Scope (явно)

Эти пункты НЕ делаются в этом плане, чтобы не раздуть скоуп:

- **Полная миграция с Supabase на PocketBase для контактов и истории сообщений.** Только call-сигналинг. История звонков (`recordIncomingCall`, `markIncomingCallDeclined`, `markCurrentUserCallEnded`) **остаётся** в Supabase в этом плане.
- **Деплой PocketBase на конкретный сервер.** Только инструкция в `docs/POCKETBASE_SETUP.md` и заглушка URL в `.env`.
- **Переподключение Supabase fallback при недоступности PocketBase.** Если URL не задан — startup error, как указано в задаче 20.
- **Mesh-конференции на 3–4 человека.** В коде закладываем `roomId` (не `chatId`) и `targetUserId` (не один peer per call), модель `RtcMessage` уже многопользовательская — но логика создания нескольких PeerConnection остаётся в `webrtc_call_screen_native_impl.dart` 1:1 как сейчас. Расширение до Mesh — отдельный план.
- **Шифрование payload SDP/ICE.** SDP не содержит секретов; `payload` хранится в plain JSON. Если потребуется E2E-обёртка — добавляется отдельным шагом.

## Риски и mitigations

| Риск | Mitigation |
|------|-----------|
| PocketBase `subscribe` filter не поддерживает сложные выражения | Проверить версию SDK; в крайнем случае фильтровать клиентски в `_onRecord`. |
| PocketBase Dart SDK **не работает на web** (плохая поддержка SSE в браузерах) | Проверить в задаче 1 (`pub.dev/packages/pocketbase`); если SDK не поддерживает web — реализовать тонкий REST + EventSource fallback в `WebRtcSignalingService` для web-платформы (через `dart:html` EventSource). |
| Auth-flow PocketBase усложняет регистрацию первого юзера | Lazy auth в задаче 7 + технический email — не требует UI-изменений. |
| Незакоммиченные WIP-изменения смешаются с новой работой при `git checkout -b` | См. Pre-flight: коммитим/стэшим до создания ветки. |
| Web migration увеличивает размер плана и риск регрессий на web-платформе | Тест `flutter build web` в Definition of Done; ручной прогон `pw-test/two-browser-call.mjs` (если PocketBase поднят). |
| Cleanup записей `rtc_signaling`: коллекция растёт неограниченно | См. задачу 21 — cron-хук в PocketBase для TTL=1час. Без этого через несколько недель БД распухнет. |

## Definition of Done

- [ ] Звонок 1-на-1 между двумя устройствами (native+native, web+web, native+web) проходит через PocketBase без вызова какого-либо метода `SupabaseService.send*Call*` или `SupabaseService.subscribe*Calls`.
- [ ] В логах `[stealth-call]` присутствуют записи `[signaling] send type=offer` / `[signaling] recv type=answer`, RTP-пакеты идут (по `[rtc-stats]`).
- [x] `flutter test` проходит для всех unit-тестов signaling. (25 passed, 1 skipped — smoke без `POCKETBASE_TEST_URL`.)
- [ ] `flutter build web` собирается без ошибок.
- [ ] `flutter build apk --debug` собирается без ошибок.
- [ ] `flutter analyze` без warnings.
- [ ] Hangup от одной стороны корректно закрывает экран на другой стороне в течение 2 секунд (вместо 15+ сек ICE timeout).
- [ ] Имитация разрыва сети (выключение Wi-Fi на 5 сек во время звонка) восстанавливает signaling-канал автоматически.
- [x] `docs/POCKETBASE_SETUP.md` содержит рабочий docker-compose, схему коллекции и API rules.
- [x] `client/.env.example` содержит `POCKETBASE_URL`, `TURNS_URL`, `TURNS_USERNAME`, `TURNS_PASSWORD`.
- [ ] `CALL_BUG_ANALYSIS.md` обновлён или удалён (проблема устранена).
