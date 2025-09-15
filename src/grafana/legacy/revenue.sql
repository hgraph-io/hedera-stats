-----------------------
-- total revenue
-----------------------
create or replace function ecosystem.dashboard_revenue(
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
    select sum(charged_tx_fee) into previous_total
    from transaction
    where consensus_timestamp between previous_period_start and current_period_start;

    select sum(charged_tx_fee) into total
    from transaction
    where consensus_timestamp >= current_period_start;

  return query select total, previous_total;
end
$$ language plpgsql;
