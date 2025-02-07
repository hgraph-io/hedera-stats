create or replace function ecosystem.dashboard_active_accounts(
    _interval interval
)
returns decimal as $$

declare
total decimal;
previous_period_start bigint = (NOW() - _interval * 2)::timestamp9::bigint;
current_period_start bigint = (NOW() - _interval )::timestamp9::bigint;

begin
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
  return total;
end;
$$ language plpgsql;
