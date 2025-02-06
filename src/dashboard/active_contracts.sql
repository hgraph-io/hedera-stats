-----------------------
-- Total active smart contracts
-- select ecosystem.dashboard_active_contracts('90 days');
-- select ecosystem.dashboard_active_contracts('7 days', true);
-- select ecosystem.dashboard_active_contracts('30 days', true);
-- select ecosystem.dashboard_active_contracts('90 days', true);
-----------------------
create or replace function ecosystem.dashboard_active_contracts(
    _interval interval, change boolean = false
)
returns decimal as $$
declare total decimal;
begin
  -- get percent change
  if change then
    WITH time_bounds AS (
        SELECT
            (NOW() - _interval * 2)::timestamp9::bigint AS previous_period_start,
            (NOW() - _interval)::timestamp9::bigint AS current_period_start
    ),
    previous_period AS (
      select count(distinct cr.contract_id) as total
      from contract_result cr
      JOIN time_bounds tb ON
          cr.consensus_timestamp BETWEEN tb.previous_period_start AND tb.current_period_start
      and cr.transaction_result = 22 -- success result
    ),
    current_period AS (
      select count(distinct cr.contract_id) as total
      from contract_result cr
      JOIN time_bounds tb ON
          cr.consensus_timestamp >= tb.current_period_start
      and cr.transaction_result = 22 -- success result
    )
    SELECT
        ((current_period.total::DECIMAL / NULLIF(previous_period.total, 0)) - 1) * 100 into total
    FROM current_period, previous_period;
  else
    select count(distinct cr.contract_id) into total
    from contract_result cr
    where cr.consensus_timestamp >= (NOW() - _interval)::timestamp9::bigint
    and cr.transaction_result = 22; -- success result
  end if;
  return total;
end;
$$ language plpgsql;
