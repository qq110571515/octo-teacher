create table if not exists platform_screen_time_redemptions (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  child_profile_id uuid not null references platform_child_profiles(id) on delete cascade,
  device_id uuid not null references platform_family_devices(id) on delete cascade,
  redemption_ref uuid not null,
  receipt_hash text not null check (receipt_hash ~ '^[a-f0-9]{64}$'),
  points integer not null check (points between 1 and 1000000),
  minutes integer not null check (minutes between 15 and 240),
  policy_revision integer not null check (policy_revision > 0),
  selection_hash text not null check (selection_hash ~ '^[a-f0-9]{64}$'),
  control_command_id text not null check (char_length(control_command_id) between 1 and 160),
  target_token_hash text not null check (target_token_hash ~ '^[a-f0-9]{64}$'),
  unlock_until timestamptz not null,
  state text not null default 'reserved'
    check (state in ('reserved', 'committed', 'cancelled', 'expired')),
  expires_at timestamptz not null,
  committed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_profile_id, redemption_ref)
);

create index if not exists platform_screen_time_redemptions_active_idx
  on platform_screen_time_redemptions (child_profile_id, expires_at)
  where state = 'reserved';

create index if not exists platform_screen_time_redemptions_family_idx
  on platform_screen_time_redemptions (family_id);

create index if not exists platform_screen_time_redemptions_device_idx
  on platform_screen_time_redemptions (device_id);

alter table platform_screen_time_redemptions enable row level security;
revoke all on table platform_screen_time_redemptions from anon, authenticated;

comment on table platform_screen_time_redemptions is
  'Two-phase Screen Time point spends. A child device reserves points before changing ManagedSettings and commits only after verified local enforcement.';
