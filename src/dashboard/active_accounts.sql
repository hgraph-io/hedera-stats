-----------------------
-- Total active accounts
-----------------------
-- drop function ecosystem.dashboard_active_accounts;
create or replace function ecosystem.dashboard_active_accounts(
    _interval interval
)
returns bigint as $$
  select count(*) as total from (
    select distinct payer_account_id
    from transaction
    where consensus_timestamp >= (now() - _interval::interval)::timestamp9::bigint
    and result = 22
  );
$$ language sql;
