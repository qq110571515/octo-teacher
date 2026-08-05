create extension if not exists pgcrypto;

create table if not exists platform_accounts (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null unique,
  handle text not null,
  display_name text not null,
  email_hash char(64) check (email_hash is null or email_hash ~ '^[0-9a-f]{64}$'),
  email_masked text,
  status text not null default 'active' check (status in ('pending', 'active', 'suspended', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists platform_accounts_handle_unique_idx
  on platform_accounts (lower(handle))
  where status <> 'deleted';
create unique index if not exists platform_accounts_email_hash_unique_idx
  on platform_accounts (email_hash)
  where email_hash is not null and status <> 'deleted';

create table if not exists platform_account_identities (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references platform_accounts(id) on delete cascade,
  provider text not null check (provider in ('email_magic_link', 'apple')),
  provider_subject text not null,
  status text not null default 'active' check (status in ('active', 'revoked')),
  verified_at timestamptz not null,
  last_used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, provider_subject)
);

create table if not exists platform_account_sessions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references platform_accounts(id) on delete cascade,
  token_hash char(64) not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  client_kind text not null check (client_kind in ('web', 'ios')),
  device_public_ref text,
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists platform_beta_invites (
  id uuid primary key default gen_random_uuid(),
  code_hash char(64) not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  label text not null,
  status text not null default 'active' check (status in ('active', 'exhausted', 'expired', 'revoked')),
  max_uses integer not null default 1 check (max_uses between 1 and 1000),
  use_count integer not null default 0 check (use_count between 0 and max_uses),
  expires_at timestamptz not null,
  created_by_operator_ref_hash char(64) not null check (created_by_operator_ref_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create table if not exists platform_email_login_challenges (
  id uuid primary key default gen_random_uuid(),
  email_hash char(64) not null check (email_hash ~ '^[0-9a-f]{64}$'),
  challenge_hash char(64) not null unique check (challenge_hash ~ '^[0-9a-f]{64}$'),
  beta_invite_id uuid references platform_beta_invites(id),
  purpose text not null check (purpose in ('register', 'sign_in', 'link_identity')),
  status text not null default 'issued' check (status in ('issued', 'consumed', 'expired', 'blocked')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 5),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table platform_guardian_accounts
  add column if not exists account_id uuid references platform_accounts(id);

create unique index if not exists platform_guardian_accounts_account_unique_idx
  on platform_guardian_accounts (account_id)
  where account_id is not null;

create table if not exists marketplace_creator_accounts (
  account_id uuid primary key references platform_accounts(id) on delete cascade,
  creator_id text not null unique references marketplace_creators(id),
  status text not null default 'applicant' check (status in ('applicant', 'active', 'suspended', 'revoked')),
  applied_at timestamptz not null default now(),
  activated_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists platform_account_identities_account_idx
  on platform_account_identities (account_id, status);
create index if not exists platform_account_sessions_lookup_idx
  on platform_account_sessions (token_hash, expires_at)
  where revoked_at is null;
create index if not exists platform_email_login_challenges_lookup_idx
  on platform_email_login_challenges (email_hash, purpose, created_at desc);

alter table platform_accounts enable row level security;
alter table platform_account_identities enable row level security;
alter table platform_account_sessions enable row level security;
alter table platform_beta_invites enable row level security;
alter table platform_email_login_challenges enable row level security;
alter table marketplace_creator_accounts enable row level security;

comment on table platform_accounts is 'One human Octo Teacher account shared by web and iOS; it is distinct from a family and from login identities.';
comment on table platform_account_identities is 'Verified login identities. Apple is linkable and must not create a duplicate account automatically.';
comment on table platform_beta_invites is 'Closed-beta admission only. It never replaces account authentication or family authorization.';
comment on table marketplace_creator_accounts is 'Explicit creator capability for an account; it grants no access to family or child data.';
