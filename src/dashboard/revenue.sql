-----------------------
-- total revenue
-----------------------
create or replace function ecosystem.dashboard_revenue(
    _interval interval
)
returns bigint as $$
    select sum(charged_tx_fee)
    from transaction
    where consensus_timestamp >= (now() - _interval::interval)::timestamp9::bigint
$$ language sql;
