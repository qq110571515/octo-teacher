alter table platform_family_task_changes
  drop constraint if exists platform_family_task_changes_task_id_task_version_key;

alter table platform_family_task_changes
  drop constraint if exists platform_family_task_changes_change_kind_check;

alter table platform_family_task_changes
  add constraint platform_family_task_changes_change_kind_check
  check (change_kind in ('created', 'updated', 'submitted', 'withdrawn'));

create unique index if not exists platform_family_task_changes_task_version_child_idx
  on platform_family_task_changes (task_id, task_version, child_profile_id);

comment on index platform_family_task_changes_task_version_child_idx is
  'Allows one task version to notify both the previous and current child when a guardian reassigns it.';
