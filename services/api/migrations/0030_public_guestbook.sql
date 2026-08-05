create table if not exists public_guestbook_messages (
  id bigint generated always as identity primary key,
  display_name text not null,
  message text not null,
  ip_hash text not null,
  content_hash text not null,
  moderation_status text not null default 'visible',
  created_at timestamptz not null default now(),
  constraint public_guestbook_messages_display_name_check
    check (char_length(display_name) between 1 and 40),
  constraint public_guestbook_messages_message_check
    check (char_length(message) between 10 and 600),
  constraint public_guestbook_messages_ip_hash_check
    check (ip_hash ~ '^[0-9a-f]{64}$'),
  constraint public_guestbook_messages_content_hash_check
    check (content_hash ~ '^[0-9a-f]{64}$'),
  constraint public_guestbook_messages_status_check
    check (moderation_status in ('visible', 'hidden'))
);

create index if not exists public_guestbook_messages_visible_created_idx
  on public_guestbook_messages (created_at desc)
  where moderation_status = 'visible';

create index if not exists public_guestbook_messages_ip_created_idx
  on public_guestbook_messages (ip_hash, created_at desc);

alter table public_guestbook_messages enable row level security;
revoke all on table public_guestbook_messages from anon, authenticated;
revoke all on sequence public_guestbook_messages_id_seq from anon, authenticated;

drop policy if exists public_guestbook_no_data_api_access on public_guestbook_messages;
create policy public_guestbook_no_data_api_access
  on public_guestbook_messages
  as restrictive
  for all
  to anon, authenticated
  using (false)
  with check (false);

comment on table public_guestbook_messages is
  'Public website guestbook. Raw IP addresses are never stored; ip_hash exists only for abuse prevention.';
