-- Swift's JSONEncoder omits optional nil fields. Normal chores, creative work,
-- exercise and other non-reading tasks therefore do not carry readingMode or
-- bookResource keys. They are valid v2 tasks and must not be quarantined.
with repaired as (
  update platform_family_tasks
  set delivery_status = 'ready',
      quarantine_reason = null,
      version = version + 1,
      updated_at = now()
  where delivery_status = 'quarantined'
    and quarantine_reason = 'invalid_task_payload_v2'
    and jsonb_typeof(task_payload) = 'object'
    and task_payload->'version' = '2'::jsonb
    and jsonb_typeof(task_payload->'task') = 'object'
    and (
      not (task_payload->'task' ? 'reading')
      or task_payload #> '{task,reading}' = 'null'::jsonb
    )
    and (
      not (task_payload ? 'readingMode')
      or task_payload->'readingMode' = 'null'::jsonb
    )
    and (
      not (task_payload ? 'contentReadiness')
      or task_payload->>'contentReadiness' = 'not_required'
    )
    and (
      not (task_payload ? 'bookResource')
      or task_payload->'bookResource' = 'null'::jsonb
    )
  returning id, family_id, child_profile_id, version
)
insert into platform_family_task_changes (
  family_id,
  child_profile_id,
  task_id,
  task_version,
  change_kind
)
select
  family_id,
  child_profile_id,
  id,
  version,
  'updated'
from repaired
on conflict (task_id, task_version, child_profile_id) do nothing;

comment on column platform_family_tasks.delivery_status is
  'Server-owned child delivery gate. Non-reading v2 tasks may omit nil reading fields; quarantined tasks remain guardian-visible.';
