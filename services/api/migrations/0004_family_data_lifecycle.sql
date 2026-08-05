create table if not exists platform_deletion_receipts (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('family')),
  subject_ref_hash char(64) not null check (subject_ref_hash ~ '^[0-9a-f]{64}$'),
  actor_ref_hash char(64) not null check (actor_ref_hash ~ '^[0-9a-f]{64}$'),
  deleted_counts jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists platform_deletion_receipts_created_idx
  on platform_deletion_receipts (created_at desc);

alter table platform_deletion_receipts enable row level security;

comment on table platform_deletion_receipts is
  'Privacy-safe proof that a family deletion completed. Stores hashes and aggregate counts only.';
