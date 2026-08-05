create table if not exists platform_family_sync_requests (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  actor_kind text not null check (actor_kind in ('guardian', 'child_device')),
  actor_ref_hash char(64) not null check (actor_ref_hash ~ '^[0-9a-f]{64}$'),
  mutation_ref text not null check (char_length(mutation_ref) between 8 and 160),
  created_at timestamptz not null default now(),
  unique (family_id, actor_kind, actor_ref_hash, mutation_ref)
);

create table if not exists platform_family_task_changes (
  cursor bigint generated always as identity primary key,
  family_id uuid not null references platform_families(id) on delete cascade,
  child_profile_id uuid not null references platform_child_profiles(id) on delete cascade,
  task_id uuid not null references platform_family_tasks(id) on delete cascade,
  task_version integer not null check (task_version > 0),
  change_kind text not null check (change_kind in ('created', 'updated', 'submitted')),
  created_at timestamptz not null default now(),
  unique (task_id, task_version)
);

insert into platform_family_task_changes (
  family_id, child_profile_id, task_id, task_version, change_kind, created_at
)
select family_id, child_profile_id, id, version, 'created', updated_at
from platform_family_tasks
on conflict (task_id, task_version) do nothing;

create index if not exists platform_family_sync_requests_lookup_idx
  on platform_family_sync_requests (family_id, actor_kind, actor_ref_hash, mutation_ref);
create index if not exists platform_family_task_changes_family_cursor_idx
  on platform_family_task_changes (family_id, cursor);
create index if not exists platform_family_task_changes_child_cursor_idx
  on platform_family_task_changes (child_profile_id, cursor);

alter table platform_family_sync_requests enable row level security;
alter table platform_family_task_changes enable row level security;

comment on table platform_family_sync_requests is
  'Idempotency receipts for minimal family task mutations. Payloads and child evidence are never stored here.';
comment on table platform_family_task_changes is
  'Monotonic cursor log for minimal task-state synchronization across guardian and child devices.';
