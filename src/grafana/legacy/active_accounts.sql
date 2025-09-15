-----------------------
-- Total active accounts
-----------------------
create or replace function ecosystem.dashboard_active_accounts(
    _interval interval
)
returns table (
    total bigint,
    previous_total bigint
) as $$

declare
  total bigint;
  previous_total bigint;

  previous_period_start bigint = (now() - _interval * 2)::timestamp9::bigint;
  current_period_start bigint = (now() - _interval )::timestamp9::bigint;
begin
  with t as (
    select * from transaction
    where consensus_timestamp between previous_period_start and current_period_start
    and result = 22
  )
  select count(*) into previous_total from (
    select distinct payer_account_id from t
  );

  with t as (
    select * from transaction
    where consensus_timestamp >= current_period_start
    and result = 22
  )
  select count(*) into total from (
    select distinct payer_account_id from t
  );

  return query select total, previous_total;
end
$$ language plpgsql;
