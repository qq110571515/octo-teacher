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
  old_row jsonb;
  new_row jsonb;
begin
  if tg_op <> 'INSERT' then
    old_row := to_jsonb(old);
  end if;
  if tg_op <> 'DELETE' then
    new_row := to_jsonb(new);
  end if;

  if tg_op = 'UPDATE' then
    if tg_table_name = 'platform_families'
      and old_row -> 'display_name' is not distinct from new_row -> 'display_name'
      and old_row -> 'status' is not distinct from new_row -> 'status' then
      return new;
    elsif tg_table_name = 'platform_family_guardians'
      and old_row -> 'status' is not distinct from new_row -> 'status'
      and old_row -> 'is_creator' is not distinct from new_row -> 'is_creator' then
      return new;
    elsif tg_table_name = 'platform_family_devices'
      and old_row -> 'status' is not distinct from new_row -> 'status'
      and old_row -> 'display_name' is not distinct from new_row -> 'display_name'
      and old_row -> 'guardian_id' is not distinct from new_row -> 'guardian_id'
      and old_row -> 'child_profile_id' is not distinct from new_row -> 'child_profile_id' then
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
