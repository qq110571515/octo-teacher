create index if not exists platform_family_portal_link_codes_family_idx
  on platform_family_portal_link_codes (family_id, created_at desc);

create index if not exists platform_family_portal_link_codes_consumed_account_idx
  on platform_family_portal_link_codes (consumed_by_account_id)
  where consumed_by_account_id is not null;

create index if not exists platform_family_activity_events_device_idx
  on platform_family_activity_events (device_id)
  where device_id is not null;

create index if not exists platform_family_activity_events_guardian_idx
  on platform_family_activity_events (guardian_id)
  where guardian_id is not null;
