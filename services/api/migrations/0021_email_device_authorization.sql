create extension if not exists pgcrypto;

create table if not exists platform_mobile_login_requests (
  id uuid primary key default gen_random_uuid(),
  code_hash char(64) not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  request_token_hash char(64) not null unique check (request_token_hash ~ '^[0-9a-f]{64}$'),
  device_ref_hash char(64) not null check (device_ref_hash ~ '^[0-9a-f]{64}$'),
  device_name text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'consumed', 'expired', 'revoked')),
  approved_by_account_id uuid references platform_accounts(id) on delete cascade,
  expires_at timestamptz not null,
  approved_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists platform_mobile_login_requests_device_idx
  on platform_mobile_login_requests (device_ref_hash, created_at desc);
create index if not exists platform_mobile_login_requests_pending_idx
  on platform_mobile_login_requests (status, expires_at)
  where status in ('pending', 'approved');

alter table platform_mobile_login_requests enable row level security;
revoke all on table platform_mobile_login_requests from anon, authenticated;

comment on table platform_mobile_login_requests is
  'Short-lived email-account device authorization. Plaintext codes and polling tokens are returned once and never stored.';
