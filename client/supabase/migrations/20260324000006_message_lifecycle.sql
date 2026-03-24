-- Жизненный цикл сообщений: редактирование, мягкое удаление, закреплённые сообщения.

alter table messages
    add column if not exists edited_at timestamp with time zone,
    add column if not exists deleted_at timestamp with time zone;

create table if not exists pinned_messages (
    chat_id uuid not null references chats(id) on delete cascade,
    message_id uuid not null references messages(id) on delete cascade,
    pinned_by_user_id uuid not null references users(id) on delete cascade,
    created_at timestamp with time zone not null default now(),
    primary key (chat_id, message_id)
);

create index if not exists idx_pinned_messages_chat
on pinned_messages(chat_id, created_at desc);
