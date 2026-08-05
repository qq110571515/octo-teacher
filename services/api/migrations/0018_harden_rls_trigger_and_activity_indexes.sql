revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

create index if not exists platform_family_activity_events_child_idx
  on platform_family_activity_events (child_profile_id);
