-- =========================================
-- УПРОЩЕННАЯ СХЕМА ДЛЯ STEALTH МЕССЕНДЖЕРА
-- =========================================
-- Убраны RLS политики, добавлена таблица users,
-- упрощена схема сообщений без партиционирования

-- =========================================
-- Расширения
-- =========================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =========================================
-- Таблица пользователей
-- =========================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nickname TEXT NOT NULL,
    public_key TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =========================================
-- Таблица контактов
-- =========================================
CREATE TABLE IF NOT EXISTS contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

-- =========================================
-- Таблица чатов
-- =========================================
CREATE TABLE IF NOT EXISTS chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    is_private BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =========================================
-- Таблица участников чатов
-- =========================================
CREATE TABLE IF NOT EXISTS chat_members (
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    typing BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (chat_id, user_id)
);

-- =========================================
-- Таблица сообщений (упрощенная, без партиционирования)
-- =========================================
CREATE TABLE IF NOT EXISTS messages (
    id BIGSERIAL PRIMARY KEY,
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text',
    reply_to_id BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- =========================================
-- Индексы для производительности
-- =========================================
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_metadata_gin ON messages USING gin(metadata jsonb_path_ops);

-- =========================================
-- Триггер для обновления updated_at чата
-- =========================================
CREATE OR REPLACE FUNCTION update_chat_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chats
    SET updated_at = NOW()
    WHERE id = NEW.chat_id;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_chat_timestamp ON messages;
CREATE TRIGGER trigger_update_chat_timestamp
AFTER INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION update_chat_timestamp();

-- =========================================
-- Функции для работы с сообщениями
-- =========================================

-- Вставка сообщения
CREATE OR REPLACE FUNCTION send_message(
    p_chat_id UUID,
    p_sender_id UUID,
    p_content TEXT,
    p_type TEXT DEFAULT 'text',
    p_reply_to_id BIGINT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS BIGINT AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO messages(chat_id, sender_id, content, message_type, reply_to_id, metadata)
    VALUES(p_chat_id, p_sender_id, p_content, p_type, p_reply_to_id, p_metadata)
    RETURNING id INTO v_id;

    -- Обновляем last_read_at у отправителя
    UPDATE chat_members
    SET last_read_at = NOW()
    WHERE chat_id = p_chat_id AND user_id = p_sender_id;

    RETURN v_id;
END
$$ LANGUAGE plpgsql;

-- Получение истории чата
DROP FUNCTION IF EXISTS get_chat_messages(UUID, INT);

CREATE OR REPLACE FUNCTION get_chat_messages(
    p_chat_id UUID,
    p_limit INT DEFAULT 50
) RETURNS TABLE (
    id BIGINT,
    chat_id UUID,
    sender_id UUID,
    content TEXT,
    message_type TEXT,
    reply_to_id BIGINT,
    created_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB,
    unread BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.chat_id,
        m.sender_id,
        m.content,
        m.message_type,
        m.reply_to_id,
        m.created_at,
        m.metadata,
        CASE WHEN m.created_at > cm.last_read_at THEN TRUE ELSE FALSE END AS unread
    FROM messages m
    JOIN chat_members cm ON cm.chat_id = m.chat_id AND cm.user_id = auth.uid()
    WHERE m.chat_id = p_chat_id
    ORDER BY m.created_at DESC
    LIMIT p_limit;
END
$$ LANGUAGE plpgsql STABLE;

-- =========================================
-- Управление статусом "печатает"
-- =========================================
CREATE OR REPLACE FUNCTION set_typing_status(
    p_chat_id UUID,
    p_user_id UUID,
    p_typing BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE chat_members
    SET typing = p_typing
    WHERE chat_id = p_chat_id AND user_id = p_user_id;
END
$$ LANGUAGE plpgsql;

-- =========================================
-- Массовая информация для фронта: кто печатает и непрочитанные сообщения
-- =========================================
DROP FUNCTION IF EXISTS get_realtime_chat_status(UUID);

CREATE OR REPLACE FUNCTION get_realtime_chat_status(
    p_user_id UUID
) RETURNS TABLE (
    chat_id UUID,
    is_typing BOOLEAN,
    typing_user_ids UUID[],
    unread_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        cm.chat_id,
        EXISTS (
            SELECT 1
            FROM chat_members cm2
            WHERE cm2.chat_id = cm.chat_id
              AND cm2.user_id != cm.user_id
              AND cm2.typing = TRUE
        )::BOOLEAN AS is_typing,
        ARRAY(
            SELECT cm2.user_id
            FROM chat_members cm2
            WHERE cm2.chat_id = cm.chat_id
              AND cm2.user_id != cm.user_id
              AND cm2.typing = TRUE
        )::UUID[] AS typing_user_ids,
        COUNT(*) FILTER (
            WHERE m.sender_id != cm.user_id
              AND m.created_at > cm.last_read_at
        ) AS unread_count
    FROM chat_members cm
    LEFT JOIN messages m ON m.chat_id = cm.chat_id
    WHERE cm.user_id = p_user_id
    GROUP BY cm.chat_id, cm.user_id, cm.last_read_at
    ORDER BY cm.chat_id;
END
$$ LANGUAGE plpgsql STABLE;

-- =========================================
-- Тестовые данные
-- =========================================

-- Вставляем тестовых пользователей
INSERT INTO users (id, nickname, public_key) VALUES
('11111111-1111-1111-1111-111111111111', 'POCO', 'test_public_key_poco'),
('22222222-2222-2222-2222-222222222222', 'GEEKOM', 'test_public_key_geekom')
ON CONFLICT (id) DO NOTHING;

-- Создаем приватный чат между POCO и GEEKOM
INSERT INTO chats (id, name) VALUES
('a93ecc1c-dc42-4ed4-9c53-ba9264875265', 'POCO & GEEKOM')
ON CONFLICT (id) DO NOTHING;

-- Добавляем участников в чат
INSERT INTO chat_members (chat_id, user_id) VALUES
('a93ecc1c-dc42-4ed4-9c53-ba9264875265', '11111111-1111-1111-1111-111111111111'),
('a93ecc1c-dc42-4ed4-9c53-ba9264875265', '22222222-2222-2222-2222-222222222222')
ON CONFLICT (chat_id, user_id) DO NOTHING;

-- Добавляем тестовые сообщения
INSERT INTO messages (chat_id, sender_id, content, message_type, created_at) VALUES
('a93ecc1c-dc42-4ed4-9c53-ba9264875265', '22222222-2222-2222-2222-222222222222', 'Привет! Всё хорошо, спасибо!', 'text', NOW() - INTERVAL '50 minutes'),
('a93ecc1c-dc42-4ed4-9c53-ba9264875265', '11111111-1111-1111-1111-111111111111', 'Отлично! Давай созвонимся?', 'text', NOW() - INTERVAL '30 minutes'),
('a93ecc1c-dc42-4ed4-9c53-ba9264875265', '22222222-2222-2222-2222-222222222222', 'Конечно! Звони когда удобно', 'text', NOW() - INTERVAL '15 minutes')
ON CONFLICT DO NOTHING;