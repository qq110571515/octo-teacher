alter table platform_child_profiles
  add column if not exists screen_time_emergency jsonb not null default '{
    "schemaVersion":1,
    "status":"idle",
    "updatedAt":""
  }'::jsonb;

alter table platform_child_profiles
  drop constraint if exists platform_child_profiles_screen_time_emergency_check,
  add constraint platform_child_profiles_screen_time_emergency_check
    check (
      jsonb_typeof(screen_time_emergency) = 'object'
      and screen_time_emergency->>'schemaVersion' = '1'
      and screen_time_emergency->>'status' in (
        'idle', 'requested', 'approved', 'denied', 'active', 'completed', 'expired'
      )
    );

comment on column platform_child_profiles.screen_time_emergency is
  'Minimal cross-device school-mode emergency unlock state. Timestamps and approvals are server-authored; no app identifiers are stored.';
