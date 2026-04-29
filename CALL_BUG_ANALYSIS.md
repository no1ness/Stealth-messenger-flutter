# Анализ проблемы со звонками

## Проблема
Звонки между устройствами не работают. При инициации звонка с эмулятора на телефон не появляется диалог входящего звонка.

## Диагностика

### Что работает
1. ✅ Appium тест успешно находит кнопку "Start call" на эмуляторе
2. ✅ Кнопка нажимается и звонок инициируется
3. ✅ TURN сервер настроен (`turn:openrelay.metered.ca`)
4. ✅ Локальный медиа-стрим создается на обоих устройствах
5. ✅ `CallManager` активен (обернут вокруг `MainTabs`)

### Что не работает
1. ❌ Кнопка "Answer" не появляется на телефоне (диалог входящего звонка не показывается)
2. ❌ Звонок завершается по таймауту через 120 секунд
3. ❌ Нет логов о получении `call_initiation` на телефоне
4. ❌ Нет логов о получении `call_accept` на эмуляторе
5. ❌ Offer/Answer не обмениваются между устройствами

### Логи

#### Эмулятор (caller)
```
04-29 16:36:13.994 I/flutter: [stealth-call] TURN configured: turn:openrelay.metered.ca:80,...
04-29 16:36:14.175 I/flutter: [stealth-call] local stream ready: audio=1 ids=[...] enabled=[true]
04-29 16:36:14.347 I/flutter: [stealth-call] speakerphone=true
```

**Проблема**: Нет логов о получении `call_accept` и создании offer!

#### Телефон (callee)
```
04-29 19:38:14.250 I/flutter: [stealth-call] _hangUp() isCaller=false connected=false closing=false
```

**Проблема**: Нет логов о получении `call_initiation`! `CallManager` не получает событие входящего звонка.

## Корневая причина

### Проблема 1: Supabase Realtime не доставляет события
Похоже что события `call_initiation` и `call_accept` не доставляются через Supabase Realtime broadcast каналы.

Возможные причины:
1. **Приложение не подписано на `user_calls` канал** - `CallManager` должен вызывать `subscribeToUserCalls`, но возможно подписка не активна
2. **Supabase Realtime не работает** - возможно проблема с подключением к Realtime
3. **Broadcast события не доставляются** - возможно проблема с конфигурацией Supabase

### Проблема 2: Архитектура сигналинга
Текущая архитектура:
1. Caller отправляет `call_initiation` в `user_calls:$calleeUserId`
2. Callee получает `call_initiation` через `CallManager.subscribeToUserCalls`
3. Callee показывает диалог и при нажатии Answer отправляет `call_accept` в `user_calls:$callerUserId`
4. Caller получает `call_accept` через `subscribeToUserCalls` → `_callAcceptedController.add()`
5. `WebRTCCallScreen` у caller получает событие из `callAcceptedStream` и создает offer
6. Offer/Answer/ICE обмениваются через `chat_calls:$chatId`

**Слабое место**: Зависимость от двух разных каналов (`user_calls` для инициации, `chat_calls` для WebRTC сигналинга).

## Решение

### Вариант 1: Проверить подписку на user_calls (быстрое решение)
1. Добавить детальное логирование в `CallManager`:
   - Лог при вызове `subscribeToUserCalls`
   - Лог при получении любого события в `user_calls`
   - Лог статуса Realtime подключения

2. Проверить что `CallManager` действительно подписывается на канал при запуске

### Вариант 2: Упростить архитектуру (надежное решение)
Использовать только `chat_calls` канал для всего сигналинга:
1. Caller отправляет `call_initiation` в `chat_calls:$chatId`
2. Callee подписывается на `chat_calls:$chatId` сразу при запуске приложения
3. Все события (initiation, accept, offer, answer, ice, end) идут через один канал

Преимущества:
- Проще отлаживать (один канал вместо двух)
- Меньше точек отказа
- Не нужно знать `userId` собеседника заранее (достаточно `chatId`)

### Вариант 3: Использовать Supabase Database вместо Realtime
Вместо broadcast использовать таблицу `call_signals`:
```sql
CREATE TABLE call_signals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  chat_id UUID NOT NULL,
  from_user_id UUID NOT NULL,
  signal_type TEXT NOT NULL, -- 'initiation', 'accept', 'offer', 'answer', 'ice', 'end'
  payload JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
```

Преимущества:
- Гарантированная доставка (в отличие от broadcast)
- Можно посмотреть историю сигналов для отладки
- Работает даже если одно устройство оффлайн (сигналы сохраняются)

## Рекомендация
Начать с **Варианта 1** (добавить логирование) чтобы понять точную причину проблемы, затем при необходимости перейти к **Варианту 2** или **Варианту 3**.

## Следующие шаги
1. Добавить детальное логирование в `CallManager`
2. Проверить статус Supabase Realtime подключения
3. Проверить что `subscribeToUserCalls` вызывается при запуске
4. Если проблема в Realtime - рассмотреть переход на Database-based сигналинг
