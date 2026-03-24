-- =========================================
-- ВКЛЮЧЕНИЕ И НАСТРОЙКА ROW LEVEL SECURITY
-- =========================================
-- Эта миграция включает RLS для всех важных таблиц и добавляет
-- правила доступа, основанные на auth.uid() от Supabase Auth.
-- Требуется анонимная авторизация (signInAnonymously) на клиенте.

-- Вспомогательная функция для проверки участия в чате.
-- Используется SECURITY DEFINER для обхода рекурсивных проверок политик
CREATE OR REPLACE FUNCTION is_chat_member(c_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_members cm 
    WHERE cm.chat_id = c_id AND cm.user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;

-- =========================================
-- users
-- =========================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users are viewable by everyone" ON public.users 
  FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile" ON public.users 
  FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "Users can update their own profile" ON public.users 
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY "Users can delete their own profile" ON public.users 
  FOR DELETE USING (id = auth.uid());

-- =========================================
-- contacts
-- =========================================
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own contacts" ON public.contacts 
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- =========================================
-- chats
-- =========================================
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;

-- Любой аутентифицированный пользователь может создать чат
CREATE POLICY "Users can create chats" ON public.chats 
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Читать и изменять могут только участники чата
CREATE POLICY "Members can view chats" ON public.chats 
  FOR SELECT USING (is_chat_member(id));

CREATE POLICY "Members can update chats" ON public.chats 
  FOR UPDATE USING (is_chat_member(id));

-- =========================================
-- chat_members
-- =========================================
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;

-- Читать список могут участники этого же чата
CREATE POLICY "Members can view other members" ON public.chat_members 
  FOR SELECT USING (is_chat_member(chat_id));

-- Добавление новых участников (создатель чата добавляет себя и собеседника)
-- Разрешаем добавлять других пользователей, если мы сами авторизованы 
-- (позже можно ужесточить: добавлять может только тот, кто уже участник, но для нового чата нужно исключение)
CREATE POLICY "Users can insert chat members" ON public.chat_members 
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Обновление статусов typing, last_seen: только сам пользователь для своей строки
CREATE POLICY "Users can update their own membership" ON public.chat_members 
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- =========================================
-- messages
-- =========================================
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Чтение сообщений: только участники чата
CREATE POLICY "Members can view messages" ON public.messages 
  FOR SELECT USING (is_chat_member(chat_id));

-- Отправка сообщений: только участники чата и только от своего имени (sender_id)
CREATE POLICY "Members can insert messages" ON public.messages 
  FOR INSERT WITH CHECK (is_chat_member(chat_id) AND sender_id = auth.uid());

-- Редактирование и мягкое удаление (deleted_at): только автор сообщения
CREATE POLICY "Authors can update messages" ON public.messages 
  FOR UPDATE USING (sender_id = auth.uid()) WITH CHECK (sender_id = auth.uid());

-- =========================================
-- pinned_messages
-- =========================================
ALTER TABLE public.pinned_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view pinned messages" ON public.pinned_messages 
  FOR SELECT USING (is_chat_member(chat_id));

-- Участники могут закреплять и откреплять (удалять строку) сообщения
CREATE POLICY "Members can insert pinned messages" ON public.pinned_messages 
  FOR INSERT WITH CHECK (is_chat_member(chat_id) AND pinned_by_user_id = auth.uid());

CREATE POLICY "Members can delete pinned messages" ON public.pinned_messages 
  FOR DELETE USING (is_chat_member(chat_id));

-- =========================================
-- group_key_envelopes
-- =========================================
ALTER TABLE public.group_key_envelopes ENABLE ROW LEVEL SECURITY;

-- Каждый пользователь может прочитать свой зашифрованный ключ группы
CREATE POLICY "Users can view their own envelopes" ON public.group_key_envelopes 
  FOR SELECT USING (is_chat_member(chat_id) AND user_id = auth.uid());

-- Тот, кто проводит rekey (wrapped_by_user_id), может добавлять новые ключи другим участникам
CREATE POLICY "Members can insert envelopes" ON public.group_key_envelopes 
  FOR INSERT WITH CHECK (is_chat_member(chat_id) AND wrapped_by_user_id = auth.uid());

CREATE POLICY "Members can update envelopes" ON public.group_key_envelopes 
  FOR UPDATE USING (is_chat_member(chat_id) AND wrapped_by_user_id = auth.uid());

-- =========================================
-- call_history
-- =========================================
ALTER TABLE public.call_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view call history" ON public.call_history 
  FOR SELECT USING (is_chat_member(chat_id));

CREATE POLICY "Members can insert calls" ON public.call_history 
  FOR INSERT WITH CHECK (
    is_chat_member(chat_id) AND 
    (initiator_user_id = auth.uid() OR recipient_user_id = auth.uid())
  );

CREATE POLICY "Members can update calls" ON public.call_history 
  FOR UPDATE USING (
    is_chat_member(chat_id) AND 
    (initiator_user_id = auth.uid() OR recipient_user_id = auth.uid())
  );
