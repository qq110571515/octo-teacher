alter table platform_child_profiles
  add column if not exists screen_time_catalog jsonb;

alter table platform_child_profiles
  drop constraint if exists platform_child_profiles_screen_time_catalog_check,
  add constraint platform_child_profiles_screen_time_catalog_check
    check (screen_time_catalog is null or jsonb_typeof(screen_time_catalog) = 'object');

comment on column platform_child_profiles.screen_time_catalog is
  'Latest child-device-captured opaque FamilyControls catalog. Guardians author policies; catalogs never enforce directly.';
