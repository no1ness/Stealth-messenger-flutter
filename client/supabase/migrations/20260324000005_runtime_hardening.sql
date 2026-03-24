-- Ужесточение ограничений целостности, совместимое с текущей моделью клиента.
-- Избегает auth.uid()-базированного RLS, т.к. клиент использует
-- локальные идентификаторы вместо сессий Supabase Auth.

alter table chats
    alter column name drop not null;

alter table contacts
    add constraint contacts_not_self check (user_id <> contact_user_id);

alter table chat_members
    add constraint chat_members_typing_requires_joined_at
    check (joined_at is not null);

alter table messages
    add constraint messages_content_not_empty
    check (content is not null and length(btrim(content)) > 0);

alter table messages
    add constraint messages_type_allowed
    check (message_type in ('text', 'image', 'audio', 'file'));

create index if not exists idx_contacts_unique_pair
on contacts(user_id, contact_user_id);

create index if not exists idx_group_key_envelopes_chat
on group_key_envelopes(chat_id, updated_at desc);

create or replace function touch_typing_timestamp()
returns trigger as $$
begin
    if new.typing is true then
        new.joined_at = coalesce(new.joined_at, now());
    end if;
    return new;
end
$$ language plpgsql;

drop trigger if exists trigger_touch_typing_timestamp on chat_members;
create trigger trigger_touch_typing_timestamp
before update on chat_members
for each row execute function touch_typing_timestamp();

create or replace function keep_reply_reference_in_chat()
returns trigger as $$
declare
    v_chat_id uuid;
begin
    if new.reply_to_id is null then
        return new;
    end if;

    select chat_id into v_chat_id
    from messages
    where id = new.reply_to_id;

    if v_chat_id is null or v_chat_id <> new.chat_id then
        raise exception 'reply_to_id must reference a message from the same chat';
    end if;

    return new;
end
$$ language plpgsql;

drop trigger if exists trigger_keep_reply_reference_in_chat on messages;
create trigger trigger_keep_reply_reference_in_chat
before insert or update on messages
for each row execute function keep_reply_reference_in_chat();
