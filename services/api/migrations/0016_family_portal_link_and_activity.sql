create table if not exists platform_family_portal_link_codes (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  guardian_id uuid not null references platform_guardian_accounts(id) on delete cascade,
  code_hash char(64) not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'issued' check (status in ('issued', 'consumed', 'revoked', 'expired')),
  expires_at timestamptz not null,
  consumed_by_account_id uuid references platform_accounts(id) on delete set null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists platform_family_activity_events (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  child_profile_id uuid not null references platform_child_profiles(id) on delete cascade,
  device_id uuid references platform_family_devices(id) on delete set null,
  guardian_id uuid references platform_guardian_accounts(id) on delete set null,
  actor_kind text not null check (actor_kind in ('child_device', 'guardian')),
  client_ref text not null check (client_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{7,159}$'),
  kind text not null check (kind in ('task', 'reading', 'video', 'screen_time')),
  occurred_at timestamptz not null,
  duration_seconds integer check (duration_seconds is null or duration_seconds between 0 and 43200),
  progress_percent smallint check (progress_percent is null or progress_percent between 0 and 100),
  display_name text not null check (char_length(display_name) between 1 and 160),
  resource_ref text check (
    resource_ref is null or resource_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$'
  ),
  payload_hash char(64) not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  schema_version smallint not null default 1 check (schema_version = 1),
  created_at timestamptz not null default now(),
  unique (family_id, child_profile_id, actor_kind, client_ref)
);

create index if not exists platform_family_portal_link_codes_issued_idx
  on platform_family_portal_link_codes (guardian_id, family_id, expires_at desc)
  where status = 'issued';

create index if not exists platform_family_activity_events_child_time_idx
  on platform_family_activity_events (family_id, child_profile_id, occurred_at desc);

create index if not exists platform_family_activity_events_kind_time_idx
  on platform_family_activity_events (family_id, kind, occurred_at desc);

alter table platform_family_portal_link_codes enable row level security;
alter table platform_family_activity_events enable row level security;

revoke all on table platform_family_portal_link_codes from anon, authenticated;
revoke all on table platform_family_activity_events from anon, authenticated;

comment on table platform_family_portal_link_codes is
  'Short-lived one-time bridge between a guardian-authenticated family and an approved web account. Only SHA-256 code hashes are stored.';
comment on table platform_family_activity_events is
  'Sanitized family activity summaries only. Raw chats, media, evidence, book text, URLs, API keys, and FamilyControls or ManagedSettings tokens are forbidden by the API contract.';
