alter table platform_child_profiles
  add column if not exists pre_reader_mode boolean not null default false,
  add column if not exists interface_language text not null default 'chinese',
  add column if not exists content_language text not null default 'chinese',
  add column if not exists profile_version integer not null default 1;

alter table platform_child_profiles
  drop constraint if exists platform_child_profiles_interface_language_check,
  add constraint platform_child_profiles_interface_language_check
    check (interface_language in ('chinese', 'english')),
  drop constraint if exists platform_child_profiles_content_language_check,
  add constraint platform_child_profiles_content_language_check
    check (content_language in ('chinese', 'english', 'bilingual')),
  drop constraint if exists platform_child_profiles_profile_version_check,
  add constraint platform_child_profiles_profile_version_check
    check (profile_version > 0);

alter table platform_family_tasks
  add column if not exists task_payload jsonb;

comment on column platform_child_profiles.pre_reader_mode is
  'Guardian-managed child presentation mode synchronized to the bound child device.';
comment on column platform_child_profiles.interface_language is
  'Guardian-managed child UI language. This is configuration, not chat or child memory.';
comment on column platform_child_profiles.content_language is
  'Guardian-managed learning-content language for this child.';
comment on column platform_family_tasks.task_payload is
  'Versioned task instructions and safe resource metadata. It excludes proof media, chat, memory, journals, mail, and provider credentials.';
