create extension if not exists pgcrypto;

alter table platform_child_profiles
  add column if not exists client_ref text;

alter table platform_family_invites
  add column if not exists child_profile_id uuid references platform_child_profiles(id) on delete cascade;

create unique index if not exists platform_child_profiles_family_client_ref_idx
  on platform_child_profiles (family_id, client_ref)
  where client_ref is not null;

create table if not exists platform_auth_nonces (
  id uuid primary key default gen_random_uuid(),
  nonce_hash char(64) not null unique check (nonce_hash ~ '^[0-9a-f]{64}$'),
  device_ref_hash char(64) not null check (device_ref_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'issued' check (status in ('issued', 'consumed', 'expired')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists platform_guardian_sessions (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references platform_guardian_accounts(id) on delete cascade,
  token_hash char(64) not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  device_public_ref text not null,
  device_name text not null,
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists platform_guardian_consents (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references platform_guardian_accounts(id) on delete cascade,
  consent_version text not null,
  family_sync_accepted boolean not null,
  child_task_sync_accepted boolean not null,
  accepted_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (guardian_id, consent_version)
);

create table if not exists platform_family_devices (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  guardian_id uuid references platform_guardian_accounts(id) on delete cascade,
  child_profile_id uuid references platform_child_profiles(id) on delete cascade,
  public_ref text not null unique,
  display_name text not null,
  role text not null check (role in ('guardian', 'child')),
  session_token_hash char(64) unique check (session_token_hash is null or session_token_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'active' check (status in ('active', 'revoked')),
  bound_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (
    (role = 'guardian' and guardian_id is not null and child_profile_id is null and session_token_hash is null)
    or
    (role = 'child' and guardian_id is null and child_profile_id is not null and session_token_hash is not null)
  )
);

create table if not exists platform_family_tasks (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  child_profile_id uuid not null references platform_child_profiles(id) on delete cascade,
  client_ref text not null,
  title text not null,
  title_english text,
  status text not null default 'assigned' check (status in ('assigned', 'started', 'submitted', 'approved', 'rejected', 'cancelled')),
  growth_points integer not null default 0 check (growth_points between 0 and 10000),
  requires_evidence boolean not null default false,
  planned_for date,
  evidence_summary text,
  version integer not null default 1 check (version > 0),
  created_by_guardian_id uuid not null references platform_guardian_accounts(id),
  submitted_by_device_id uuid references platform_family_devices(id),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (family_id, client_ref)
);

create table if not exists platform_family_audit (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references platform_families(id) on delete cascade,
  action text not null,
  actor_kind text not null check (actor_kind in ('guardian', 'child_device', 'system')),
  actor_ref_hash char(64) not null check (actor_ref_hash ~ '^[0-9a-f]{64}$'),
  target_public_ref text,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists platform_auth_nonces_device_idx
  on platform_auth_nonces (device_ref_hash, created_at desc);
create index if not exists platform_guardian_sessions_lookup_idx
  on platform_guardian_sessions (token_hash, expires_at) where revoked_at is null;
create index if not exists platform_family_devices_family_idx
  on platform_family_devices (family_id, status, role);
create index if not exists platform_family_devices_child_session_idx
  on platform_family_devices (session_token_hash, status) where role = 'child';
create index if not exists platform_family_tasks_child_idx
  on platform_family_tasks (child_profile_id, status, planned_for, updated_at desc);
create index if not exists platform_family_audit_family_idx
  on platform_family_audit (family_id, created_at desc);

alter table platform_auth_nonces enable row level security;
alter table platform_guardian_sessions enable row level security;
alter table platform_guardian_consents enable row level security;
alter table platform_family_devices enable row level security;
alter table platform_family_tasks enable row level security;
alter table platform_family_audit enable row level security;

comment on table platform_auth_nonces is 'Short-lived Sign in with Apple replay protection. Only SHA-256 nonce hashes are stored.';
comment on table platform_guardian_sessions is 'Opaque guardian sessions. Plaintext bearer tokens are returned once and kept only in device Keychain.';
comment on table platform_guardian_consents is 'Versioned, explicit guardian consent for family metadata and minimal child task synchronization.';
comment on table platform_family_devices is 'Guardian or single-child device bindings; child devices never require email accounts.';
comment on table platform_family_tasks is 'Minimal cross-device task state. No photos, recordings, chat transcripts, or child memory are stored here.';
