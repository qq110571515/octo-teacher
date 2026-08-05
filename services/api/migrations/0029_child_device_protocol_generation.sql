alter table platform_family_devices
  add column if not exists protocol_generation smallint not null default 1;

alter table platform_family_devices
  drop constraint if exists platform_family_devices_protocol_generation_check,
  add constraint platform_family_devices_protocol_generation_check
    check (protocol_generation between 1 and 32767);

create unique index if not exists platform_family_devices_one_active_child_device_idx
  on platform_family_devices (family_id, child_profile_id)
  where role = 'child' and status = 'active';

drop trigger if exists platform_family_devices_bump_sync_version on platform_family_devices;
create trigger platform_family_devices_bump_sync_version
before update of status, display_name, guardian_id, child_profile_id, protocol_generation
on platform_family_devices
for each row when (
  old.status is distinct from new.status
  or old.display_name is distinct from new.display_name
  or old.guardian_id is distinct from new.guardian_id
  or old.child_profile_id is distinct from new.child_profile_id
  or old.protocol_generation is distinct from new.protocol_generation
) execute function platform_bump_family_device_sync_version();

comment on column platform_family_devices.protocol_generation is
  'Family API protocol generation captured at child-device binding. A newer app must rebind when this generation is stale.';
