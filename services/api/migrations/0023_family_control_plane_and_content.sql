create extension if not exists pgcrypto;

alter table platform_families
  add column if not exists sync_version bigint not null default 1;

alter table platform_family_guardians
  add column if not exists membership_version bigint not null default 1,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists revoked_at timestamptz;

alter table platform_family_devices
  add column if not exists sync_version bigint not null default 1,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists platform_family_content_items (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  public_ref text not null unique,
  client_ref text not null check (client_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{7,159}$'),
  kind text not null check (kind in ('book', 'video', 'creation')),
  title text not null check (char_length(title) between 1 and 240),
  title_english text check (title_english is null or char_length(title_english) between 1 and 240),
  source_kind text not null check (source_kind in ('marketplace', 'cloud_library', 'guardian_upload', 'external', 'generated')),
  source_ref text check (source_ref is null or char_length(source_ref) between 1 and 240),
  storage_object_key text check (storage_object_key is null or char_length(storage_object_key) between 1 and 500),
  availability text not null default 'processing' check (availability in ('processing', 'ready', 'unavailable', 'archived')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_by_guardian_id uuid not null references platform_guardian_accounts(id),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (family_id, client_ref)
);

create table if not exists platform_family_content_assignments (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references platform_families(id) on delete cascade,
  content_item_id uuid not null references platform_family_content_items(id) on delete cascade,
  child_profile_id uuid not null references platform_child_profiles(id) on delete cascade,
  status text not null default 'assigned' check (status in ('assigned', 'in_progress', 'completed', 'removed')),
  progress_percent smallint not null default 0 check (progress_percent between 0 and 100),
  duration_seconds integer not null default 0 check (duration_seconds between 0 and 31536000),
  assigned_by_guardian_id uuid not null references platform_guardian_accounts(id),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (content_item_id, child_profile_id)
);

create table if not exists platform_family_content_mutations (
  family_id uuid not null references platform_families(id) on delete cascade,
  mutation_ref text not null check (mutation_ref ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{7,159}$'),
  payload_hash char(64) not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  operation text not null check (operation in ('content_upsert', 'content_archive', 'assignment_upsert')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (family_id, mutation_ref)
);

create table if not exists platform_family_sync_changes (
  cursor bigint generated always as identity primary key,
  family_id uuid not null references platform_families(id) on delete cascade,
  child_profile_id uuid,
  entity_kind text not null check (entity_kind in (
    'family', 'guardian', 'child', 'device', 'task', 'points',
    'content', 'content_assignment', 'activity'
  )),
  entity_ref text not null check (char_length(entity_ref) between 1 and 240),
  operation text not null check (operation in ('upsert', 'remove')),
  entity_version bigint not null check (entity_version > 0),
  changed_at timestamptz not null default now()
);

create index if not exists platform_family_sync_changes_family_cursor_idx
  on platform_family_sync_changes (family_id, cursor);

create index if not exists platform_family_sync_changes_child_cursor_idx
  on platform_family_sync_changes (family_id, child_profile_id, cursor)
  where child_profile_id is not null;

create index if not exists platform_family_content_items_family_kind_idx
  on platform_family_content_items (family_id, kind, availability, updated_at desc);

create index if not exists platform_family_content_assignments_child_idx
  on platform_family_content_assignments (child_profile_id, status, updated_at desc);

create index if not exists platform_family_content_assignments_content_idx
  on platform_family_content_assignments (content_item_id);

alter table platform_family_content_items enable row level security;
alter table platform_family_content_assignments enable row level security;
alter table platform_family_content_mutations enable row level security;
alter table platform_family_sync_changes enable row level security;

revoke all on table platform_family_content_items from anon, authenticated;
revoke all on table platform_family_content_assignments from anon, authenticated;
revoke all on table platform_family_content_mutations from anon, authenticated;
revoke all on table platform_family_sync_changes from anon, authenticated;

alter table platform_family_activity_events
  drop constraint if exists platform_family_activity_events_kind_check;
alter table platform_family_activity_events
  add constraint platform_family_activity_events_kind_check
  check (kind in ('task', 'reading', 'video', 'screen_time', 'creation'));

create or replace function platform_bump_family_sync_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.sync_version := old.sync_version + 1;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function platform_bump_family_membership_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.membership_version := old.membership_version + 1;
  new.updated_at := now();
  if new.status = 'revoked' and old.status is distinct from 'revoked' then
    new.revoked_at := now();
  elsif new.status <> 'revoked' then
    new.revoked_at := null;
  end if;
  return new;
end;
$$;

create or replace function platform_bump_family_device_sync_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.sync_version := old.sync_version + 1;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function platform_record_family_sync_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_family_id uuid;
  row_child_id uuid;
  row_entity_kind text;
  row_entity_ref text;
  row_operation text;
  row_version bigint;
begin
  if tg_op = 'UPDATE' then
    if tg_table_name = 'platform_families'
      and old.display_name is not distinct from new.display_name
      and old.status is not distinct from new.status then
      return new;
    elsif tg_table_name = 'platform_family_guardians'
      and old.status is not distinct from new.status
      and old.is_creator is not distinct from new.is_creator then
      return new;
    elsif tg_table_name = 'platform_family_devices'
      and old.status is not distinct from new.status
      and old.display_name is not distinct from new.display_name
      and old.guardian_id is not distinct from new.guardian_id
      and old.child_profile_id is not distinct from new.child_profile_id then
      return new;
    end if;
  end if;
  if tg_op = 'DELETE' then
    if tg_table_name = 'platform_family_guardians' then
      row_family_id := old.family_id;
      row_entity_kind := 'guardian';
      row_entity_ref := old.guardian_id::text;
      row_version := old.membership_version;
    elsif tg_table_name = 'platform_child_profiles' then
      row_family_id := old.family_id;
      row_child_id := old.id;
      row_entity_kind := 'child';
      row_entity_ref := old.public_ref;
      row_version := old.profile_version;
    elsif tg_table_name = 'platform_family_devices' then
      row_family_id := old.family_id;
      row_child_id := old.child_profile_id;
      row_entity_kind := 'device';
      row_entity_ref := old.public_ref;
      row_version := old.sync_version;
    elsif tg_table_name = 'platform_family_tasks' then
      row_family_id := old.family_id;
      row_child_id := old.child_profile_id;
      row_entity_kind := 'task';
      row_entity_ref := old.client_ref;
      row_version := old.version;
    elsif tg_table_name = 'platform_family_content_items' then
      row_family_id := old.family_id;
      row_entity_kind := 'content';
      row_entity_ref := old.public_ref;
      row_version := old.version;
    elsif tg_table_name = 'platform_family_content_assignments' then
      row_family_id := old.family_id;
      row_child_id := old.child_profile_id;
      row_entity_kind := 'content_assignment';
      row_entity_ref := old.id::text;
      row_version := old.version;
    else
      raise exception 'unsupported_family_sync_delete_table';
    end if;
    row_operation := 'remove';
  elsif tg_table_name = 'platform_families' then
    row_family_id := new.id;
    row_entity_kind := 'family';
    row_entity_ref := new.public_ref;
    row_operation := case when new.status <> 'active' then 'remove' else 'upsert' end;
    row_version := new.sync_version;
  elsif tg_table_name = 'platform_family_guardians' then
    row_family_id := new.family_id;
    row_entity_kind := 'guardian';
    row_entity_ref := new.guardian_id::text;
    row_operation := case when new.status = 'revoked' then 'remove' else 'upsert' end;
    row_version := new.membership_version;
  elsif tg_table_name = 'platform_child_profiles' then
    row_family_id := new.family_id;
    row_child_id := new.id;
    row_entity_kind := 'child';
    row_entity_ref := new.public_ref;
    row_operation := case when new.status = 'archived' then 'remove' else 'upsert' end;
    row_version := new.profile_version;
  elsif tg_table_name = 'platform_family_devices' then
    row_family_id := new.family_id;
    row_child_id := new.child_profile_id;
    row_entity_kind := 'device';
    row_entity_ref := new.public_ref;
    row_operation := case when new.status = 'revoked' then 'remove' else 'upsert' end;
    row_version := new.sync_version;
  elsif tg_table_name = 'platform_family_tasks' then
    row_family_id := new.family_id;
    row_child_id := new.child_profile_id;
    row_entity_kind := 'task';
    row_entity_ref := new.client_ref;
    row_operation := 'upsert';
    row_version := new.version;
  elsif tg_table_name = 'platform_family_growth_point_ledger' then
    row_family_id := new.family_id;
    row_child_id := new.child_profile_id;
    row_entity_kind := 'points';
    row_entity_ref := new.id::text;
    row_operation := 'upsert';
    row_version := 1;
  elsif tg_table_name = 'platform_family_content_items' then
    row_family_id := new.family_id;
    row_entity_kind := 'content';
    row_entity_ref := new.public_ref;
    row_operation := case when new.availability = 'archived' then 'remove' else 'upsert' end;
    row_version := new.version;
  elsif tg_table_name = 'platform_family_content_assignments' then
    row_family_id := new.family_id;
    row_child_id := new.child_profile_id;
    row_entity_kind := 'content_assignment';
    row_entity_ref := new.id::text;
    row_operation := case when new.status = 'removed' then 'remove' else 'upsert' end;
    row_version := new.version;
  elsif tg_table_name = 'platform_family_activity_events' then
    row_family_id := new.family_id;
    row_child_id := new.child_profile_id;
    row_entity_kind := 'activity';
    row_entity_ref := new.id::text;
    row_operation := 'upsert';
    row_version := 1;
  else
    raise exception 'unsupported_family_sync_table';
  end if;

  insert into public.platform_family_sync_changes (
    family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
  ) values (
    row_family_id, row_child_id, row_entity_kind, row_entity_ref, row_operation, row_version
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function platform_validate_family_content_assignment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.platform_family_content_items
    where id = new.content_item_id and family_id = new.family_id
  ) or not exists (
    select 1 from public.platform_child_profiles
    where id = new.child_profile_id and family_id = new.family_id and status = 'active'
  ) then
    raise exception 'family_content_assignment_scope_mismatch';
  end if;
  return new;
end;
$$;

create or replace function platform_guardian_one_active_family()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'active' and exists (
    select 1
    from public.platform_family_guardians membership
    join public.platform_families family on family.id = membership.family_id and family.status = 'active'
    where membership.guardian_id = new.guardian_id
      and membership.status = 'active'
      and membership.family_id <> new.family_id
  ) then
    raise exception using errcode = '23505', message = 'guardian_multiple_active_families';
  end if;
  return new;
end;
$$;

create or replace function platform_child_client_ref_one_active_family()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'active' and new.client_ref is not null and exists (
    select 1
    from public.platform_child_profiles child
    join public.platform_families family on family.id = child.family_id and family.status = 'active'
    where child.client_ref = new.client_ref
      and child.status = 'active'
      and child.family_id <> new.family_id
  ) then
    raise exception using errcode = '23505', message = 'child_client_ref_family_conflict';
  end if;
  return new;
end;
$$;

drop trigger if exists platform_family_guardians_one_active_family on platform_family_guardians;
create trigger platform_family_guardians_one_active_family
before insert or update of family_id, guardian_id, status on platform_family_guardians
for each row execute function platform_guardian_one_active_family();

drop trigger if exists platform_child_profiles_client_ref_one_active_family on platform_child_profiles;
create trigger platform_child_profiles_client_ref_one_active_family
before insert or update of family_id, client_ref, status on platform_child_profiles
for each row execute function platform_child_client_ref_one_active_family();

drop trigger if exists platform_family_content_assignments_validate_scope on platform_family_content_assignments;
create trigger platform_family_content_assignments_validate_scope
before insert or update of family_id, content_item_id, child_profile_id
on platform_family_content_assignments
for each row execute function platform_validate_family_content_assignment();

drop trigger if exists platform_families_bump_sync_version on platform_families;
create trigger platform_families_bump_sync_version
before update of display_name, status on platform_families
for each row when (
  old.display_name is distinct from new.display_name or old.status is distinct from new.status
) execute function platform_bump_family_sync_version();

drop trigger if exists platform_family_guardians_bump_membership_version on platform_family_guardians;
create trigger platform_family_guardians_bump_membership_version
before update of status, is_creator on platform_family_guardians
for each row when (
  old.status is distinct from new.status or old.is_creator is distinct from new.is_creator
) execute function platform_bump_family_membership_version();

drop trigger if exists platform_family_devices_bump_sync_version on platform_family_devices;
create trigger platform_family_devices_bump_sync_version
before update of status, display_name, guardian_id, child_profile_id on platform_family_devices
for each row when (
  old.status is distinct from new.status
  or old.display_name is distinct from new.display_name
  or old.guardian_id is distinct from new.guardian_id
  or old.child_profile_id is distinct from new.child_profile_id
) execute function platform_bump_family_device_sync_version();

drop trigger if exists platform_families_record_sync_change on platform_families;
create trigger platform_families_record_sync_change
after insert or update on platform_families
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_family_guardians_record_sync_change on platform_family_guardians;
create trigger platform_family_guardians_record_sync_change
after insert or update or delete on platform_family_guardians
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_child_profiles_record_sync_change on platform_child_profiles;
create trigger platform_child_profiles_record_sync_change
after insert or update or delete on platform_child_profiles
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_family_devices_record_sync_change on platform_family_devices;
create trigger platform_family_devices_record_sync_change
after insert or update or delete on platform_family_devices
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_family_tasks_record_sync_change on platform_family_tasks;
create trigger platform_family_tasks_record_sync_change
after insert or update or delete on platform_family_tasks
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_family_growth_points_record_sync_change on platform_family_growth_point_ledger;
create trigger platform_family_growth_points_record_sync_change
after insert on platform_family_growth_point_ledger
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_family_content_items_record_sync_change on platform_family_content_items;
create trigger platform_family_content_items_record_sync_change
after insert or update or delete on platform_family_content_items
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_family_content_assignments_record_sync_change on platform_family_content_assignments;
create trigger platform_family_content_assignments_record_sync_change
after insert or update or delete on platform_family_content_assignments
for each row execute function platform_record_family_sync_change();

drop trigger if exists platform_family_activity_record_sync_change on platform_family_activity_events;
create trigger platform_family_activity_record_sync_change
after insert on platform_family_activity_events
for each row execute function platform_record_family_sync_change();

insert into platform_family_sync_changes (
  family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
)
select id, null, 'family', public_ref,
  case when status = 'active' then 'upsert' else 'remove' end, sync_version
from platform_families;

insert into platform_family_sync_changes (
  family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
)
select family_id, null, 'guardian', guardian_id::text,
  case when status = 'revoked' then 'remove' else 'upsert' end, membership_version
from platform_family_guardians;

insert into platform_family_sync_changes (
  family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
)
select family_id, id, 'child', public_ref,
  case when status = 'archived' then 'remove' else 'upsert' end, profile_version
from platform_child_profiles;

insert into platform_family_sync_changes (
  family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
)
select family_id, child_profile_id, 'device', public_ref,
  case when status = 'revoked' then 'remove' else 'upsert' end, sync_version
from platform_family_devices;

insert into platform_family_sync_changes (
  family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
)
select family_id, child_profile_id, 'task', client_ref, 'upsert', version
from platform_family_tasks;

insert into platform_family_sync_changes (
  family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
)
select family_id, child_profile_id, 'points', id::text, 'upsert', 1
from platform_family_growth_point_ledger;

insert into platform_family_sync_changes (
  family_id, child_profile_id, entity_kind, entity_ref, operation, entity_version
)
select family_id, child_profile_id, 'activity', id::text, 'upsert', 1
from platform_family_activity_events;

comment on table platform_family_sync_changes is
  'Server-only invalidation stream. Clients use the opaque cursor to detect changes, then reload an authoritative family or child snapshot instead of merging partial payloads.';
comment on table platform_family_content_items is
  'Family-scoped metadata for books, videos, and creations. Raw child media, book bytes, DRM material, API keys, and Screen Time tokens are never stored here.';
comment on table platform_family_content_assignments is
  'Minimal child assignment and progress state for family content. Detailed reading text and child evidence remain outside this table.';
comment on table platform_family_content_mutations is
  'Server-only idempotency receipts for family content writes. Payload hashes prevent a mutation reference from being reused with different data.';
comment on function platform_guardian_one_active_family() is
  'Defense-in-depth for new writes. Existing production conflicts remain untouched and must be resolved through an audited repair plan.';
comment on function platform_child_client_ref_one_active_family() is
  'Prevents new active child client references from being silently copied across active families without modifying historical conflicts.';
