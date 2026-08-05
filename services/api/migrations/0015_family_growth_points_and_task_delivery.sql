alter table platform_child_profiles
  add column if not exists growth_point_balance integer not null default 0;

alter table platform_child_profiles
  drop constraint if exists platform_child_profiles_growth_point_balance_check,
  add constraint platform_child_profiles_growth_point_balance_check
    check (growth_point_balance >= 0);

alter table platform_family_tasks
  add column if not exists delivery_status text not null default 'ready',
  add column if not exists quarantine_reason text;

alter table platform_family_tasks
  drop constraint if exists platform_family_tasks_delivery_status_check,
  add constraint platform_family_tasks_delivery_status_check
    check (delivery_status in ('ready', 'quarantined')),
  drop constraint if exists platform_family_tasks_quarantine_reason_check,
  add constraint platform_family_tasks_quarantine_reason_check
    check (
      (delivery_status = 'ready' and quarantine_reason is null)
      or
      (delivery_status = 'quarantined' and quarantine_reason is not null)
    );

create table if not exists platform_family_growth_point_ledger (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  child_profile_id uuid not null references platform_child_profiles(id) on delete cascade,
  entry_kind text not null check (entry_kind in ('task_approved', 'screen_time_spend', 'screen_time_refund')),
  delta integer not null check (delta <> 0 and delta between -1000000 and 1000000),
  balance_after integer not null check (balance_after >= 0),
  mutation_ref text not null check (char_length(mutation_ref) between 8 and 160),
  source_ref text not null check (char_length(source_ref) between 8 and 160),
  created_at timestamptz not null default now(),
  unique (child_profile_id, mutation_ref),
  unique (child_profile_id, entry_kind, source_ref)
);

create index if not exists platform_family_growth_point_ledger_family_child_idx
  on platform_family_growth_point_ledger (family_id, child_profile_id, created_at, id);

create index if not exists platform_family_growth_point_ledger_refund_source_idx
  on platform_family_growth_point_ledger (child_profile_id, source_ref)
  where entry_kind in ('screen_time_spend', 'screen_time_refund');

alter table platform_family_growth_point_ledger enable row level security;

alter table platform_family_growth_point_ledger
  drop constraint if exists platform_family_growth_point_ledger_delta_kind_check,
  add constraint platform_family_growth_point_ledger_delta_kind_check
    check (
      (entry_kind = 'task_approved' and delta > 0)
      or (entry_kind = 'screen_time_spend' and delta < 0)
      or (entry_kind = 'screen_time_refund' and delta > 0)
    );

create or replace function platform_reject_growth_point_ledger_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'growth_point_ledger_is_immutable';
end;
$$;

drop trigger if exists platform_family_growth_point_ledger_no_update
  on platform_family_growth_point_ledger;
create trigger platform_family_growth_point_ledger_no_update
before update on platform_family_growth_point_ledger
for each row execute function platform_reject_growth_point_ledger_update();

drop trigger if exists platform_family_growth_point_ledger_no_direct_delete
  on platform_family_growth_point_ledger;

revoke all on table platform_family_growth_point_ledger from anon, authenticated;

-- Legacy electronic-reading payloads do not carry the v2 readiness contract.
-- Keep them visible to guardians, but never send them to child devices.
update platform_family_tasks
set delivery_status = 'quarantined',
    quarantine_reason = case
      when jsonb_typeof(task_payload) is distinct from 'object'
        then 'invalid_task_payload'
      when task_payload->'version' is distinct from '2'::jsonb
        then 'legacy_digital_reading_mode_missing'
      when task_payload->>'readingMode' = 'digital_loaded'
        then 'digital_book_resource_missing'
      when task_payload->>'readingMode' = 'physical_manual'
        then 'physical_reading_readiness_invalid'
      else 'invalid_task_payload_v2'
    end
where task_payload is not null
  and (
    jsonb_typeof(task_payload) is distinct from 'object'
    or
    (
      task_payload->'version' is distinct from '2'::jsonb
      and (
        jsonb_typeof(task_payload->'bookResource') = 'object'
        or task_payload->>'readingMode' in ('digital_loaded', 'digital_required')
        or task_payload #>> '{task,reading,deliveryMode}' in ('digital_loaded', 'digital_required')
        or coalesce(task_payload #>> '{task,reading,importedBookId}', '') <> ''
      )
    )
    or
    (
      task_payload->'version' = '2'::jsonb
      and not (
        jsonb_typeof(task_payload->'task') = 'object'
        and (
          (
            jsonb_typeof(task_payload #> '{task,reading}') = 'object'
            and (
              (
                task_payload->>'readingMode' = 'digital_loaded'
                and task_payload->>'contentReadiness' = 'ready'
                and jsonb_typeof(task_payload->'bookResource') = 'object'
                and coalesce(task_payload->'bookResource'->>'sourceURLString', '') ~* '^https://[^[:space:]]+$'
              )
              or
              (
                task_payload->>'readingMode' = 'physical_manual'
                and task_payload->>'contentReadiness' = 'not_required'
                and (
                  not (task_payload ? 'bookResource')
                  or task_payload->'bookResource' = 'null'::jsonb
                )
              )
            )
          )
          or
          (
            (
              not (task_payload->'task' ? 'reading')
              or task_payload #> '{task,reading}' = 'null'::jsonb
            )
            and task_payload ? 'readingMode'
            and task_payload->'readingMode' = 'null'::jsonb
            and task_payload->>'contentReadiness' = 'not_required'
          )
        )
      )
    )
  );

-- Historical approvals use deterministic refs. The anti-join and unique
-- constraints make the backfill safe to replay without awarding twice.
with missing_approved_tasks as (
  select
    task.family_id,
    task.child_profile_id,
    task.id,
    task.growth_points,
    coalesce(existing.balance, 0)::integer as starting_balance
  from platform_family_tasks task
  left join (
    select child_profile_id, sum(delta)::integer as balance
    from platform_family_growth_point_ledger
    group by child_profile_id
  ) existing on existing.child_profile_id = task.child_profile_id
  where task.status = 'approved'
    and task.growth_points > 0
    and not exists (
      select 1
      from platform_family_growth_point_ledger ledger
      where ledger.child_profile_id = task.child_profile_id
        and ledger.entry_kind = 'task_approved'
        and ledger.source_ref = 'task-ref:' || task.id::text
    )
), ranked_approved_tasks as (
  select *,
    starting_balance + sum(growth_points) over (
      partition by child_profile_id
      order by id
    )::integer as running_balance
  from missing_approved_tasks
)
insert into platform_family_growth_point_ledger (
  family_id,
  child_profile_id,
  entry_kind,
  delta,
  balance_after,
  mutation_ref,
  source_ref,
  created_at
)
select
  family_id,
  child_profile_id,
  'task_approved',
  growth_points,
  running_balance,
  'task-approved:' || id::text,
  'task-ref:' || id::text,
  now()
from ranked_approved_tasks
on conflict do nothing;

update platform_child_profiles child
set growth_point_balance = coalesce((
  select sum(ledger.delta)::integer
  from platform_family_growth_point_ledger ledger
  where ledger.child_profile_id = child.id
), 0);

comment on column platform_child_profiles.growth_point_balance is
  'Server-maintained projection of the immutable family growth-point ledger.';
comment on column platform_family_tasks.delivery_status is
  'Server-owned child delivery gate. Quarantined tasks remain visible to guardians but are not sent to child devices.';
comment on table platform_family_growth_point_ledger is
  'Append-only growth-point mutations for application roles. Updates are rejected; rows are removed only through family lifecycle cascades.';
