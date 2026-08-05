create table if not exists platform_account_approval_audit (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references platform_accounts(id) on delete cascade,
  action text not null check (action in ('requested', 'approved', 'suspended')),
  actor_subject_hash char(64) not null check (actor_subject_hash ~ '^[0-9a-f]{64}$'),
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists platform_account_approval_audit_account_idx
  on platform_account_approval_audit (account_id, created_at desc);

alter table platform_account_approval_audit enable row level security;

comment on table platform_account_approval_audit is
  'Owner-reviewed closed-beta admission audit. Never stores tokens, raw email, child data, or AI content.';
