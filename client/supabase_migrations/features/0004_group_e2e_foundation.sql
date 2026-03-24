-- Основа группового E2E-шифрования для общих ключей чата.
-- Каждый участник хранит групповой ключ, зашифрованный его личным ключом.

create table if not exists group_key_envelopes (
    chat_id uuid not null references chats(id) on delete cascade,
    user_id uuid not null references users(id) on delete cascade,
    wrapped_by_user_id uuid not null references users(id) on delete cascade,
    encrypted_key text not null,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now(),
    primary key (chat_id, user_id)
);

create index if not exists idx_group_key_envelopes_user
on group_key_envelopes(user_id, updated_at desc);
