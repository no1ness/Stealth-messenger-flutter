-- Роли участников группы для модерации.

alter table chat_members
    add column if not exists role text not null default 'member';

alter table chat_members
    add constraint chat_members_role_allowed
    check (role in ('admin', 'member'));

create index if not exists idx_chat_members_role
on chat_members(chat_id, role);
