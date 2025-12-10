-- =========================================
-- ПОЛНЫЙ СБРОС И ПЕРЕСОЗДАНИЕ БАЗЫ ДАННЫХ STEALTH
-- Используйте этот скрипт для полной очистки и настройки БД
-- =========================================

-- =========================================
-- ШАГ 1: Удаление всех таблиц и зависимостей
-- =========================================
DROP TABLE IF EXISTS message_reads CASCADE;
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS chat_members CASCADE;
DROP TABLE IF EXISTS chats CASCADE;
DROP TABLE IF EXISTS contacts CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Удаление функций
DROP FUNCTION IF EXISTS get_user_chats(UUID) CASCADE;
DROP FUNCTION IF EXISTS get_chat_messages(UUID, UUID, INT, TIMESTAMP WITH TIME ZONE) CASCADE;
DROP FUNCTION IF EXISTS set_typing_status(UUID, UUID, BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS mark_messages_read(UUID, UUID, UUID[]) CASCADE;
DROP FUNCTION IF EXISTS create_private_chat(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS update_chat_timestamp() CASCADE;
DROP FUNCTION IF EXISTS update_user_timestamp() CASCADE;

-- =========================================
-- ШАГ 2: Создание новой схемы
-- =========================================

-- Расширения
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Таблица пользователей
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nickname TEXT,
    public_key TEXT,
    avatar_url TEXT,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT now(),
    is_online BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Таблица контактов
CREATE TABLE contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE(user_id, contact_user_id)
);

-- Таблица чатов
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT, -- NULL для приватных чатов
    is_group BOOLEAN DEFAULT FALSE,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Таблица участников чатов
CREATE TABLE chat_members (
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    last_read_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    typing BOOLEAN DEFAULT FALSE,
    typing_at TIMESTAMP WITH TIME ZONE,
    role TEXT DEFAULT 'member', -- 'admin', 'member'
    PRIMARY KEY (chat_id, user_id)
);

-- Таблица сообщений
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT,
    message_type TEXT DEFAULT 'text', -- 'text', 'image', 'audio', 'file'
    reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    metadata JSONB DEFAULT '{}'::jsonb, -- для дополнительных данных
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE -- мягкое удаление
);

-- Таблица прочитанных сообщений
CREATE TABLE message_reads (
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    PRIMARY KEY (message_id, user_id)
);

-- =========================================
-- ШАГ 3: Индексы для производительности
-- =========================================
CREATE INDEX idx_users_nickname ON users(nickname);
CREATE INDEX idx_users_last_seen ON users(last_seen);
CREATE INDEX idx_contacts_user_id ON contacts(user_id);
CREATE INDEX idx_contacts_contact_user_id ON contacts(contact_user_id);
CREATE INDEX idx_chats_updated_at ON chats(updated_at DESC);
CREATE INDEX idx_chats_is_group ON chats(is_group);
CREATE INDEX idx_chat_members_chat_id ON chat_members(chat_id);
CREATE INDEX idx_chat_members_user_id ON chat_members(user_id);
CREATE INDEX idx_chat_members_last_read_at ON chat_members(last_read_at);
CREATE INDEX idx_chat_members_typing ON chat_members(typing) WHERE typing = TRUE;
CREATE INDEX idx_messages_chat_id ON messages(chat_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX idx_messages_chat_created ON messages(chat_id, created_at DESC);
CREATE INDEX idx_messages_metadata_gin ON messages USING gin(metadata jsonb_path_ops);
CREATE INDEX idx_message_reads_message_id ON message_reads(message_id);
CREATE INDEX idx_message_reads_user_id ON message_reads(user_id);

-- =========================================
-- ШАГ 4: Триггеры
-- =========================================

-- Обновление updated_at в чатах при новых сообщениях
CREATE OR REPLACE FUNCTION update_chat_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chats
    SET updated_at = NEW.created_at
    WHERE id = NEW.chat_id;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_chat_timestamp
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION update_chat_timestamp();

-- Обновление updated_at в пользователях
CREATE OR REPLACE FUNCTION update_user_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_timestamp
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_user_timestamp();

-- =========================================
-- ШАГ 5: RLS (Row Level Security)
-- =========================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reads ENABLE ROW LEVEL SECURITY;

-- Пользователи: все могут видеть всех (для поиска контактов)
CREATE POLICY "Users are viewable by everyone" ON users FOR SELECT USING (true);

-- Контакты: только владелец может видеть и управлять
CREATE POLICY "Users can view their own contacts" ON contacts FOR SELECT USING (user_id = auth.uid()::uuid);
CREATE POLICY "Users can add contacts" ON contacts FOR INSERT WITH CHECK (user_id = auth.uid()::uuid);
CREATE POLICY "Users can update their contacts" ON contacts FOR UPDATE USING (user_id = auth.uid()::uuid);
CREATE POLICY "Users can delete their contacts" ON contacts FOR DELETE USING (user_id = auth.uid()::uuid);

-- Чаты: участники могут видеть свои чаты
CREATE POLICY "Chat members can view chats" ON chats FOR SELECT USING (
    EXISTS (SELECT 1 FROM chat_members WHERE chat_id = chats.id AND user_id = auth.uid()::uuid)
);

-- Участники чатов: участники могут видеть состав чата
CREATE POLICY "Chat members can view membership" ON chat_members FOR SELECT USING (
    user_id = auth.uid()::uuid OR
    chat_id IN (SELECT chat_id FROM chat_members WHERE user_id = auth.uid()::uuid)
);

-- Сообщения: только участники чата могут видеть сообщения
CREATE POLICY "Chat members can view messages" ON messages FOR SELECT USING (
    EXISTS (SELECT 1 FROM chat_members WHERE chat_id = messages.chat_id AND user_id = auth.uid()::uuid)
);
CREATE POLICY "Chat members can send messages" ON messages FOR INSERT WITH CHECK (
    sender_id = auth.uid()::uuid AND
    EXISTS (SELECT 1 FROM chat_members WHERE chat_id = messages.chat_id AND user_id = auth.uid()::uuid)
);

-- Прочитанные сообщения: только участники могут отмечать
CREATE POLICY "Chat members can mark messages as read" ON message_reads FOR INSERT WITH CHECK (
    user_id = auth.uid()::uuid AND
    EXISTS (SELECT 1 FROM chat_members WHERE chat_id = (SELECT chat_id FROM messages WHERE id = message_reads.message_id) AND user_id = auth.uid()::uuid)
);
CREATE POLICY "Users can view read status" ON message_reads FOR SELECT USING (
    user_id = auth.uid()::uuid OR
    EXISTS (SELECT 1 FROM messages m JOIN chat_members cm ON m.chat_id = cm.chat_id WHERE m.id = message_reads.message_id AND cm.user_id = auth.uid()::uuid)
);

-- =========================================
-- ШАГ 6: Функции
-- =========================================

-- Получение чатов пользователя с последним сообщением и статусами
CREATE OR REPLACE FUNCTION get_user_chats(p_user_id UUID)
RETURNS TABLE (
    chat_id UUID,
    chat_name TEXT,
    is_group BOOLEAN,
    last_message TEXT,
    last_message_time TIMESTAMP WITH TIME ZONE,
    unread_count BIGINT,
    is_typing BOOLEAN,
    typing_users TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        COALESCE(c.name, (
            SELECT u.nickname
            FROM chat_members cm2
            JOIN users u ON u.id = cm2.user_id
            WHERE cm2.chat_id = c.id AND cm2.user_id != p_user_id
            LIMIT 1
        )) as chat_name,
        c.is_group,
        m.content as last_message,
        m.created_at as last_message_time,
        COUNT(*) FILTER (WHERE mr.message_id IS NULL AND m.sender_id != p_user_id) as unread_count,
        EXISTS (SELECT 1 FROM chat_members WHERE chat_id = c.id AND user_id != p_user_id AND typing = TRUE) as is_typing,
        ARRAY(
            SELECT u.nickname
            FROM chat_members cm3
            JOIN users u ON u.id = cm3.user_id
            WHERE cm3.chat_id = c.id AND cm3.user_id != p_user_id AND cm3.typing = TRUE
        ) as typing_users
    FROM chat_members cm
    JOIN chats c ON c.id = cm.chat_id
    LEFT JOIN messages m ON m.chat_id = c.id
    LEFT JOIN message_reads mr ON mr.message_id = m.id AND mr.user_id = p_user_id
    WHERE cm.user_id = p_user_id
        AND m.created_at = (
            SELECT MAX(created_at)
            FROM messages
            WHERE chat_id = c.id
        )
    GROUP BY c.id, c.name, c.is_group, m.content, m.created_at
    ORDER BY m.created_at DESC NULLS LAST;
END
$$ LANGUAGE plpgsql STABLE;

-- Получение сообщений чата с пагинацией
CREATE OR REPLACE FUNCTION get_chat_messages(
    p_chat_id UUID,
    p_user_id UUID,
    p_limit INT DEFAULT 50,
    p_before TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    sender_id UUID,
    sender_nickname TEXT,
    content TEXT,
    message_type TEXT,
    reply_to_id UUID,
    created_at TIMESTAMP WITH TIME ZONE,
    edited_at TIMESTAMP WITH TIME ZONE,
    is_read BOOLEAN,
    read_by UUID[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.sender_id,
        u.nickname as sender_nickname,
        m.content,
        m.message_type,
        m.reply_to_id,
        m.created_at,
        m.edited_at,
        CASE WHEN m.sender_id = p_user_id THEN TRUE
             ELSE EXISTS (SELECT 1 FROM message_reads WHERE message_id = m.id AND user_id = p_user_id)
        END as is_read,
        ARRAY(
            SELECT user_id
            FROM message_reads
            WHERE message_id = m.id
        ) as read_by
    FROM messages m
    JOIN users u ON u.id = m.sender_id
    WHERE m.chat_id = p_chat_id
        AND m.deleted_at IS NULL
        AND (p_before IS NULL OR m.created_at < p_before)
    ORDER BY m.created_at DESC
    LIMIT p_limit;
END
$$ LANGUAGE plpgsql STABLE;

-- Обновление статуса "печатает"
CREATE OR REPLACE FUNCTION set_typing_status(
    p_chat_id UUID,
    p_user_id UUID,
    p_typing BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE chat_members
    SET typing = p_typing,
        typing_at = CASE WHEN p_typing THEN now() ELSE NULL END
    WHERE chat_id = p_chat_id AND user_id = p_user_id;
END
$$ LANGUAGE plpgsql;

-- Отметить сообщения как прочитанные
CREATE OR REPLACE FUNCTION mark_messages_read(
    p_chat_id UUID,
    p_user_id UUID,
    p_message_ids UUID[]
) RETURNS VOID AS $$
BEGIN
    INSERT INTO message_reads (message_id, user_id)
    SELECT unnest(p_message_ids), p_user_id
    ON CONFLICT (message_id, user_id) DO NOTHING;

    UPDATE chat_members
    SET last_read_at = now()
    WHERE chat_id = p_chat_id AND user_id = p_user_id;
END
$$ LANGUAGE plpgsql;

-- Создание приватного чата
CREATE OR REPLACE FUNCTION create_private_chat(
    p_user1_id UUID,
    p_user2_id UUID
) RETURNS UUID AS $$
DECLARE
    v_chat_id UUID;
BEGIN
    -- Проверить, существует ли уже чат
    SELECT c.id INTO v_chat_id
    FROM chats c
    JOIN chat_members cm1 ON cm1.chat_id = c.id AND cm1.user_id = p_user1_id
    JOIN chat_members cm2 ON cm2.chat_id = c.id AND cm2.user_id = p_user2_id
    WHERE c.is_group = FALSE;

    IF v_chat_id IS NOT NULL THEN
        RETURN v_chat_id;
    END IF;

    -- Создать новый чат
    INSERT INTO chats (is_group, created_by) VALUES (FALSE, p_user1_id)
    RETURNING id INTO v_chat_id;

    -- Добавить участников
    INSERT INTO chat_members (chat_id, user_id) VALUES
    (v_chat_id, p_user1_id),
    (v_chat_id, p_user2_id);

    RETURN v_chat_id;
END
$$ LANGUAGE plpgsql;

-- =========================================
-- ШАГ 7: Realtime публикации
-- =========================================
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE chats;
ALTER PUBLICATION supabase_realtime ADD TABLE chat_members;
ALTER PUBLICATION supabase_realtime ADD TABLE message_reads;

-- =========================================
-- ШАГ 8: Тестовые данные
-- =========================================
INSERT INTO users (id, nickname, public_key) VALUES
('11111111-1111-1111-1111-111111111111'::uuid, 'POCO', 'poco_public_key'),
('22222222-2222-2222-2222-222222222222'::uuid, 'GEEKOM', 'geekom_public_key')
ON CONFLICT (id) DO NOTHING;

INSERT INTO contacts (user_id, contact_user_id, name) VALUES
('11111111-1111-1111-1111-111111111111'::uuid, '22222222-2222-2222-2222-222222222222'::uuid, 'GEEKOM'),
('22222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'POCO')
ON CONFLICT (user_id, contact_user_id) DO NOTHING;

-- Создать тестовый чат через функцию
SELECT create_private_chat(
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
);

-- Добавить тестовые сообщения
INSERT INTO messages (chat_id, sender_id, content, message_type, created_at) VALUES
((SELECT id FROM chats WHERE is_group = FALSE LIMIT 1), '11111111-1111-1111-1111-111111111111'::uuid, 'Привет! Как дела?', 'text', now() - INTERVAL '1 hour'),
((SELECT id FROM chats WHERE is_group = FALSE LIMIT 1), '22222222-2222-2222-2222-222222222222'::uuid, 'Привет! Всё хорошо, спасибо!', 'text', now() - INTERVAL '50 minutes'),
((SELECT id FROM chats WHERE is_group = FALSE LIMIT 1), '11111111-1111-1111-1111-111111111111'::uuid, 'Отлично! Давай созвонимся?', 'text', now() - INTERVAL '30 minutes'),
((SELECT id FROM chats WHERE is_group = FALSE LIMIT 1), '22222222-2222-2222-2222-222222222222'::uuid, 'Конечно! Звони когда удобно', 'text', now() - INTERVAL '15 minutes')
ON CONFLICT DO NOTHING;

-- =========================================
-- ГОТОВО! База данных полностью пересоздана.
-- =========================================