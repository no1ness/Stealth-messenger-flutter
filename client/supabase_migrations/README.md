# Миграции базы данных Stealth Messenger

## Структура

```
supabase_migrations/
├── schema/                        # Базовая схема БД
│   └── 0001_init_schema.sql       # Таблицы, индексы, триггеры, тестовые данные
├── features/                      # Новый функционал
│   ├── 0003_storage_and_call_history.sql  # Хранилище файлов + история звонков
│   ├── 0004_group_e2e_foundation.sql      # Групповое E2E-шифрование
│   ├── 0006_message_lifecycle.sql         # Редактирование, удаление, закреп
│   └── 0007_group_roles.sql               # Роли участников (admin/member)
└── hardening/                     # Целостность и валидация данных
    ├── 0005_runtime_hardening.sql # Constraint'ы, проверки, триггеры
    ├── 0008_enable_rls.sql        # Настройка Row Level Security (RLS)
    └── 0009_rate_limiting.sql     # Защита от спама (Rate Limiting)
```

## Описание миграций

### `schema/0001_init_schema.sql` — Базовая схема
**Что создаёт:**
- Таблицы: `users`, `contacts`, `chats`, `chat_members`, `messages`
- Индексы на `chat_id`, `sender_id`, `created_at`, `metadata` (GIN)
- Триггер `update_chat_timestamp` — обновляет `chats.updated_at` при новом сообщении
- Функции: `send_message`, `get_chat_messages`, `set_typing_status`, `get_realtime_chat_status`
- Тестовые данные: пользователи POCO и GEEKOM с приватным чатом

**Когда применять:** При первом развёртывании БД

---

### `features/0003_storage_and_call_history.sql` — Медиа-хранилище и звонки
**Что создаёт:**
- Storage-бакет `chat-media` (50 МБ, поддержка изображений и аудио)
- Storage-политики для публичного чтения и авторизованной записи
- Таблицу `call_history` с индексами
- Функцию `upsert_call_history_event` для записи звонков

**Зависимости:** Требует `0001`

---

### `features/0004_group_e2e_foundation.sql` — Групповое шифрование
**Что создаёт:**
- Таблицу `group_key_envelopes` для хранения обёрток (encrypted) групповых ключей
- Индекс по `user_id` для быстрого поиска конвертов

**Зависимости:** Требует `0001`

---

### `hardening/0005_runtime_hardening.sql` — Ограничения целостности
**Что добавляет:**
- `chats.name` — разрешает NULL (для приватных чатов)
- `contacts_not_self` — запрет добавления себя в контакты
- `messages_content_not_empty` — проверка непустого содержимого
- `messages_type_allowed` — допустимые типы: text, image, audio, file
- Триггер `keep_reply_reference_in_chat` — reply_to только из того же чата
- Триггер `touch_typing_timestamp` — обновление joined_at при typing

**Зависимости:** Требует `0001`, `0004`

---

### `features/0006_message_lifecycle.sql` — Жизненный цикл сообщений
**Что добавляет:**
- Колонки `edited_at` и `deleted_at` в `messages`
- Таблицу `pinned_messages` для закреплённых сообщений
- Индекс для быстрого поиска закреплённых сообщений

**Зависимости:** Требует `0001`

---

### `features/0007_group_roles.sql` — Роли участников группы
**Что добавляет:**
- Колонку `role` в `chat_members` (значения: `admin`, `member`)
- Constraint `chat_members_role_allowed`
- Индекс для быстрого поиска по ролям

**Зависимости:** Требует `0001`

### `hardening/0008_enable_rls.sql` — Настройка Row Level Security (RLS)
**Что добавляет:**
- Включает RLS для `users`, `contacts`, `chats`, `chat_members`, `messages`, `pinned_messages`, `group_key_envelopes`, `call_history`.
- Добавляет `is_chat_member()` для безопасной проверки прав доступа к чатам без рекурсии.
- Настраивает строгие RLS политики на чтение, запись, обновление и удаление для всех таблиц (например, чтение сообщений только для участников чата).

**Зависимости:** Требует `0001` - `0007`

### `hardening/0009_rate_limiting.sql` — Защита от спама (Rate Limiting)
**Что добавляет:**
- Создаёт триггер `enforce_message_rate_limit` на таблицу `messages`.
- Ограничивает отправку до 15 сообщений за 10 секунд от одного пользователя.
- Предотвращает флуд и переполнение базы данных.

**Зависимости:** Требует `0001`

---

## Как применять

### Включение Anonymous Auth (ОБЯЗАТЕЛЬНО ПРОЧТИТЕ В ПЕРВУЮ ОЧЕРЕДЬ)
С версии с внедренным RLS клиентское приложение требует возможности делать анонимный вход (`signInAnonymously()`). Без него RLS заблокирует все запросы.
1. Откройте ваш проект в **Supabase Dashboard**
2. Перейдите в **Authentication** -> **Providers**
3. Включите провайдер **Anonymous Sign-Ins**
4. Сохраните изменения.

### Первое развёртывание (новая БД)
Выполнить скрипты **строго в порядке нумерации** через SQL-редактор Supabase:

```bash
# 1. Базовая схема
schema/0001_init_schema.sql

# 2. Медиа-хранилище и звонки
features/0003_storage_and_call_history.sql

# 3. Групповое шифрование
features/0004_group_e2e_foundation.sql

# 4. Ограничения целостности
hardening/0005_runtime_hardening.sql

# 5. Жизненный цикл сообщений
features/0006_message_lifecycle.sql

# 6. Роли участников
features/0007_group_roles.sql

# 7. Row Level Security (RLS)
hardening/0008_enable_rls.sql

# 8. Защита от спама
hardening/0009_rate_limiting.sql
```

### Через Supabase Dashboard
1. Открыть **SQL Editor** в Supabase Dashboard
2. Скопировать содержимое каждого файла
3. Выполнить в указанном порядке
4. Проверить отсутствие ошибок

### Через CLI (если установлен supabase-cli)
```bash
supabase db push
```

> **⚠️ Внимание:** Миграция `0001` содержит тестовые данные (POCO, GEEKOM). Для продакшна удалите блок «Тестовые данные» в конце файла.
