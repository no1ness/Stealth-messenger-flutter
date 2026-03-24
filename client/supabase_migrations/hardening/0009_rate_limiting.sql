-- =========================================
-- ЗАЩИТА ОТ СПАМА И ФЛУДА (RATE LIMITING)
-- =========================================
-- Этот скрипт добавляет ограничение на частоту отправки сообщений
-- на уровне базы данных PostgreSQL для защиты от спама.

-- Создаем функцию для проверки частоты сообщений
CREATE OR REPLACE FUNCTION check_message_rate_limit()
RETURNS trigger AS $$
DECLARE
  recent_count INTEGER;
  max_messages_per_window CONSTANT INTEGER := 15; -- Максимум сообщений
  window_seconds CONSTANT INTEGER := 10;          -- За период (секунд)
BEGIN
  -- Считаем сообщения отправителя за последние X секунд
  SELECT count(*)
  INTO recent_count
  FROM messages
  WHERE sender_id = NEW.sender_id
    AND created_at > NOW() - (window_seconds || ' seconds')::interval;
    
  IF recent_count >= max_messages_per_window THEN
    RAISE EXCEPTION 'Rate limit exceeded: You can only send % messages per % seconds.', max_messages_per_window, window_seconds;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Создаем (или пересоздаем) триггер, вызывающий функцию перед INSERT
DROP TRIGGER IF EXISTS enforce_message_rate_limit ON messages;

CREATE TRIGGER enforce_message_rate_limit
BEFORE INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION check_message_rate_limit();
