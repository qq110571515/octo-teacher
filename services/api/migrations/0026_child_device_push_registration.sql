alter table platform_family_devices
  add column if not exists push_token text,
  add column if not exists push_environment text,
  add column if not exists push_token_updated_at timestamptz;

alter table platform_family_devices
  drop constraint if exists platform_family_devices_push_token_format_check;

alter table platform_family_devices
  add constraint platform_family_devices_push_token_format_check check (
    (push_token is null and push_environment is null)
    or (
      role = 'child'
      and push_token ~ '^[0-9a-f]{64,200}$'
      and push_environment in ('development', 'production')
    )
  );

create unique index if not exists platform_family_devices_active_push_token_idx
  on platform_family_devices (push_token)
  where push_token is not null and status = 'active';

comment on column platform_family_devices.push_token is
  'Private APNs routing token for silent child-device policy wakeups. Never returned by family APIs or included in push payloads.';
