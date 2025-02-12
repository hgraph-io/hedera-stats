create or replace function ecosystem.dashboard_revenue(
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
      select sum(charged_tx_fee) as total
      from transaction
      where consensus_timestamp between previous_period_start and current_period_start
      and result = 22
    ),
    current_period AS (
      select sum(charged_tx_fee) as total
      from transaction
      where consensus_timestamp >= current_period_start
      and result = 22
    )
    select
        ((current_period.total::DECIMAL / nullif(previous_period.total, 0)) - 1) * 100
    into total
    from current_period, previous_period;

  -- get total count
  else
      select sum(charged_tx_fee) into total
      from transaction
      where consensus_timestamp >= current_period_start
      and result = 22;
  end if;

  -- total or percentage change
  return total;
end;
$$ language plpgsql;
