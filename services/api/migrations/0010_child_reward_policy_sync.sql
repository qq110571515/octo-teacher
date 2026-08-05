alter table platform_child_profiles
  add column if not exists daily_limit_minutes integer not null default 60,
  add column if not exists exchange_policy jsonb not null default '{
    "allowanceCycle":"monthly",
    "baseMonthlyAllowance":0,
    "allowanceDayOfMonth":1,
    "screenRate":"one_point_per_minute",
    "pointsPerCurrencyUnit":10,
    "pocketMoneyRequiresApproval":true,
    "currencySymbol":"¥"
  }'::jsonb;

alter table platform_child_profiles
  drop constraint if exists platform_child_profiles_daily_limit_minutes_check,
  add constraint platform_child_profiles_daily_limit_minutes_check
    check (daily_limit_minutes between 15 and 720),
  drop constraint if exists platform_child_profiles_exchange_policy_check,
  add constraint platform_child_profiles_exchange_policy_check
    check (jsonb_typeof(exchange_policy) = 'object');

comment on column platform_child_profiles.daily_limit_minutes is
  'Guardian-managed maximum reward-unlock minutes per local calendar day, from 15 through 720.';
comment on column platform_child_profiles.exchange_policy is
  'Guardian-managed non-sensitive Growth Point exchange rules synchronized to the bound child device.';
