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
  -- SET max_parallel_workers_per_gather = 16;

  -- get percent change
  if change then
   with previous_period AS (
      select count(*) as total from (
        SELECT distinct e.id
        FROM entity e
        INNER JOIN
          (select payer_account_id, result, consensus_timestamp from transaction) t
          ON t.payer_account_id = e.id
          AND e.type = 'ACCOUNT'
          and t.result = 22
          and t.consensus_timestamp BETWEEN previous_period_start AND current_period_start
      )
    ),
    current_period AS (
      select count(*) as total from (
        SELECT distinct e.id
        FROM entity e
        INNER JOIN
          (select payer_account_id, result, consensus_timestamp from transaction) t
          ON t.payer_account_id = e.id
          AND e.type = 'ACCOUNT'
          and t.result = 22 -- Success result
          and t.consensus_timestamp BETWEEN previous_period_start AND current_period_start
      )
    )
    SELECT
        ((current_period.total::DECIMAL / NULLIF(previous_period.total, 0)) - 1) * 100 into total
    FROM current_period, previous_period;
  else
    select count(*) into total from (
      select distinct e.id
      FROM entity e
      INNER JOIN
        (select payer_account_id, result, consensus_timestamp from transaction) t
      ON t.payer_account_id = e.id
        AND e.type = 'ACCOUNT'
        and t.result = 22
        and t.consensus_timestamp >= (now() - _interval::interval)::timestamp9::bigint
    );
  end if;
  return total;
end;
$$ language plpgsql;
