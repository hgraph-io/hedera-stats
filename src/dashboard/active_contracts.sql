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
previous_period_start bigint = (NOW() - _interval * 2)::timestamp9::bigint;
current_period_start bigint = (NOW() - _interval )::timestamp9::bigint;
begin
  -- get percent change
  if change then
    with previous_period AS (
      select count(*) as total from (
        select distinct cr.contract_id
        from contract_result cr
        where  cr.consensus_timestamp
          BETWEEN previous_period_start AND current_period_start
          and cr.transaction_result = 22 -- success result
      )
    ),
    current_period AS (
      select count(*) as total from (
        select distinct cr.contract_id
        from contract_result cr
        where cr.consensus_timestamp >= current_period_start
        and cr.transaction_result = 22 -- success result
      )
    )
    SELECT
        ((current_period.total::DECIMAL / NULLIF(previous_period.total, 0)) - 1) * 100 into total
    FROM current_period, previous_period;
  else
    select count(*) from (
      select distinct cr.contract_id into total
      from contract_result cr
      where cr.consensus_timestamp >= current_period_start
      and cr.transaction_result = 22
    );
  end if;
  return total;
end;
$$ language plpgsql;
