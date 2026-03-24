-- Хранилище файлов и история звонков.
-- Применять после базовых миграций схемы.

-- Создание публичного бакета для вложений и голосовых сообщений.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'chat-media',
    'chat-media',
    true,
    52428800,
    array[
        'image/jpeg',
        'image/png',
        'image/webp',
        'audio/aac',
        'audio/mpeg',
        'audio/mp4',
        'audio/ogg',
        'audio/wav',
        'audio/webm',
        'application/octet-stream'
    ]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Публичный доступ на чтение для простоты текущей клиентской реализации.
drop policy if exists "Public read chat media" on storage.objects;
create policy "Public read chat media"
on storage.objects for select
to public
using (bucket_id = 'chat-media');

-- Авторизованные пользователи могут загружать только в свою папку.
drop policy if exists "Authenticated upload own chat media" on storage.objects;
create policy "Authenticated upload own chat media"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'chat-media'
    and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "Authenticated update own chat media" on storage.objects;
create policy "Authenticated update own chat media"
on storage.objects for update
to authenticated
using (
    bucket_id = 'chat-media'
    and split_part(name, '/', 1) = auth.uid()::text
)
with check (
    bucket_id = 'chat-media'
    and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "Authenticated delete own chat media" on storage.objects;
create policy "Authenticated delete own chat media"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'chat-media'
    and split_part(name, '/', 1) = auth.uid()::text
);

-- Легковесная история звонков для диагностики и UI профиля.
create table if not exists call_history (
    id uuid primary key default gen_random_uuid(),
    chat_id uuid not null references chats(id) on delete cascade,
    initiator_user_id uuid not null references users(id) on delete cascade,
    recipient_user_id uuid not null references users(id) on delete cascade,
    direction text not null check (direction in ('outgoing', 'incoming')),
    status text not null check (status in ('initiated', 'accepted', 'missed', 'ended', 'declined', 'failed')),
    started_at timestamp with time zone not null default now(),
    answered_at timestamp with time zone,
    ended_at timestamp with time zone,
    duration_seconds integer not null default 0,
    metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_call_history_chat_id on call_history(chat_id);
create index if not exists idx_call_history_initiator on call_history(initiator_user_id, started_at desc);
create index if not exists idx_call_history_recipient on call_history(recipient_user_id, started_at desc);

create or replace function upsert_call_history_event(
    p_chat_id uuid,
    p_initiator_user_id uuid,
    p_recipient_user_id uuid,
    p_direction text,
    p_status text,
    p_answered_at timestamp with time zone default null,
    p_ended_at timestamp with time zone default null,
    p_metadata jsonb default '{}'::jsonb
) returns uuid as $$
declare
    v_id uuid;
begin
    select id
    into v_id
    from call_history
    where chat_id = p_chat_id
      and initiator_user_id = p_initiator_user_id
      and recipient_user_id = p_recipient_user_id
      and ended_at is null
    order by started_at desc
    limit 1;

    if v_id is null then
        insert into call_history (
            chat_id,
            initiator_user_id,
            recipient_user_id,
            direction,
            status,
            answered_at,
            ended_at,
            metadata
        )
        values (
            p_chat_id,
            p_initiator_user_id,
            p_recipient_user_id,
            p_direction,
            p_status,
            p_answered_at,
            p_ended_at,
            p_metadata
        )
        returning id into v_id;
    else
        update call_history
        set direction = p_direction,
            status = p_status,
            answered_at = coalesce(p_answered_at, answered_at),
            ended_at = coalesce(p_ended_at, ended_at),
            duration_seconds = case
                when coalesce(p_ended_at, ended_at) is not null then
                    greatest(
                        0,
                        extract(
                            epoch from coalesce(p_ended_at, ended_at) - coalesce(answered_at, started_at)
                        )::integer
                    )
                else duration_seconds
            end,
            metadata = call_history.metadata || p_metadata
        where id = v_id;
    end if;

    return v_id;
end;
$$ language plpgsql;
