create extension if not exists pgcrypto;

alter table marketplace_creators
  add column if not exists status text not null default 'active';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'marketplace_creators_status_check'
  ) then
    alter table marketplace_creators
      add constraint marketplace_creators_status_check
      check (status in ('active', 'suspended', 'deleted'));
  end if;
end $$;

create table if not exists platform_guardian_accounts (
  id uuid primary key default gen_random_uuid(),
  external_subject text not null unique,
  display_name text,
  status text not null default 'active' check (status in ('active', 'suspended', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists platform_families (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null unique,
  display_name text not null,
  created_by_guardian_id uuid not null references platform_guardian_accounts(id),
  status text not null default 'active' check (status in ('active', 'suspended', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists platform_family_guardians (
  family_id uuid not null references platform_families(id) on delete cascade,
  guardian_id uuid not null references platform_guardian_accounts(id) on delete cascade,
  membership_role text not null default 'guardian' check (membership_role = 'guardian'),
  is_creator boolean not null default false,
  status text not null default 'invited' check (status in ('invited', 'active', 'revoked')),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (family_id, guardian_id)
);

create table if not exists platform_child_profiles (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  public_ref text not null unique,
  display_name text not null,
  birth_year integer check (birth_year between 2000 and 2100),
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists platform_family_invites (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  invite_kind text not null check (invite_kind in ('guardian', 'child_device')),
  public_ref text not null unique,
  secret_hash char(64) not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  created_by_guardian_id uuid not null references platform_guardian_accounts(id),
  status text not null default 'active' check (status in ('active', 'consumed', 'expired', 'revoked')),
  max_uses integer not null default 1 check (max_uses between 1 and 20),
  use_count integer not null default 0 check (use_count between 0 and max_uses),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists marketplace_submissions (
  id uuid primary key default gen_random_uuid(),
  creator_id text not null references marketplace_creators(id),
  listing_id text not null,
  version text not null,
  payload jsonb not null,
  status text not null default 'submitted'
    check (status in ('submitted', 'changes_requested', 'approved', 'rejected', 'published', 'withdrawn')),
  terms_version text not null,
  terms_accepted_at timestamptz not null,
  submission_hash char(64) not null check (submission_hash ~ '^[0-9a-f]{64}$'),
  review_notes text,
  reviewer_ref text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (creator_id, listing_id, version)
);

create table if not exists marketplace_submission_audit (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references marketplace_submissions(id) on delete cascade,
  action text not null,
  actor_type text not null check (actor_type in ('creator', 'operator', 'system')),
  actor_ref_hash char(64) not null check (actor_ref_hash ~ '^[0-9a-f]{64}$'),
  from_status text,
  to_status text,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists platform_family_guardians_guardian_idx
  on platform_family_guardians (guardian_id, status);
create index if not exists platform_child_profiles_family_idx
  on platform_child_profiles (family_id, status);
create index if not exists platform_family_invites_lookup_idx
  on platform_family_invites (public_ref, status, expires_at);
create index if not exists marketplace_submissions_review_idx
  on marketplace_submissions (status, submitted_at desc);
create index if not exists marketplace_submission_audit_submission_idx
  on marketplace_submission_audit (submission_id, created_at);

alter table platform_guardian_accounts enable row level security;
alter table platform_families enable row level security;
alter table platform_family_guardians enable row level security;
alter table platform_child_profiles enable row level security;
alter table platform_family_invites enable row level security;
alter table marketplace_submissions enable row level security;
alter table marketplace_submission_audit enable row level security;

comment on table platform_child_profiles is 'Child profiles belong to a family and do not require email or an independent cloud login.';
comment on column platform_family_invites.secret_hash is 'SHA-256 only; plaintext QR invite secrets must never be persisted.';
comment on table marketplace_submissions is 'Creator drafts awaiting explicit operator review; never read by public clients.';
comment on table marketplace_submission_audit is 'Append-only operational audit trail for creator submission state changes.';
