-----------------------
-- Total active accounts
-- select ecosystem.dashboard_active_accounts('90 days');
-- select ecosystem.dashboard_active_accounts('90 days');
-- select ecosystem.dashboard_active_accounts('7 days', true);
-- select ecosystem.dashboard_active_accounts('30 days', true);
-- select ecosystem.dashboard_active_accounts('90 days', true);
-----------------------
create or replace function ecosystem.dashboard_active_accounts(
    _interval interval, change boolean = false
)
returns decimal as $$

declare total decimal;
previous_period_start bigint = (NOW() - _interval * 2)::timestamp9::bigint;
current_period_start bigint = (NOW() - _interval )::timestamp9::bigint;

begin
  -- get percentage change relative to previous period
  if change then
   with previous_period AS (
      select count(*) as total from (
        select distinct payer_account_id
        from transaction
        where consensus_timestamp between previous_period_start and current_period_start
        and result = 22
      )
    ),
    current_period AS (
      select count(*) as total from (
        SELECT distinct payer_account_id
        from transaction
        where consensus_timestamp >= current_period_start
        and result = 22
      )
    )
    SELECT
        ((current_period.total::DECIMAL / NULLIF(previous_period.total, 0)) - 1) * 100
    into total
    FROM current_period, previous_period;

  -- get total count
  else
    select count(*) into total from (
      select distinct payer_account_id
      from transaction
      where consensus_timestamp >= current_period_start
      and result = 22
    );

  end if;

  -- total or percentage change
  return total;
end;
$$ language plpgsql;
