-- Existing family portal links predate the unified identity bridge. Backfill the
-- native Sign in with Apple subject only when the guardian is already attached
-- to a platform account. Conflicts are intentionally left untouched for manual
-- review; identities are never merged by email or guessed automatically.
insert into platform_account_identities (
  account_id,
  provider,
  provider_subject,
  status,
  verified_at,
  last_used_at
)
select
  guardian.account_id,
  'apple',
  guardian.external_subject,
  'active',
  now(),
  now()
from platform_guardian_accounts guardian
where guardian.account_id is not null
  and guardian.status = 'active'
on conflict (provider, provider_subject) do nothing;
