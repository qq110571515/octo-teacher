alter table platform_child_profiles
  add column if not exists screen_time_policy jsonb,
  add column if not exists screen_time_status jsonb not null default '{
    "authorization":"not_requested",
    "enforcement":"waiting_for_authorization",
    "appliedPolicyRevision":null,
    "lastErrorCode":null,
    "updatedAt":""
  }'::jsonb;

alter table platform_child_profiles
  drop constraint if exists platform_child_profiles_screen_time_policy_check,
  add constraint platform_child_profiles_screen_time_policy_check
    check (screen_time_policy is null or jsonb_typeof(screen_time_policy) = 'object'),
  drop constraint if exists platform_child_profiles_screen_time_status_check,
  add constraint platform_child_profiles_screen_time_status_check
    check (jsonb_typeof(screen_time_status) = 'object');

comment on column platform_child_profiles.screen_time_policy is
  'Guardian-authored opaque FamilyControls selection and revision. Contains no app names, bundle IDs, or usage history.';
comment on column platform_child_profiles.screen_time_status is
  'Minimal child-device authorization and enforcement acknowledgement. Contains no Screen Time activity data.';
