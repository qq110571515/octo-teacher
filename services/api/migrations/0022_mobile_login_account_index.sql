create index if not exists platform_mobile_login_requests_account_idx
  on platform_mobile_login_requests (approved_by_account_id)
  where approved_by_account_id is not null;
