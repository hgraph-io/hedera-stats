create or replace function ecosystem.network_fee(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
as $$
with transactions_fee as (
        select
            consensus_timestamp,
            charged_tx_fee
        from public.transaction
        where consensus_timestamp between start_timestamp and end_timestamp
    ),
transactions_fee_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        sum(charged_tx_fee) as total
    from transactions_fee
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        coalesce((lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint, end_timestamp)
    ),
    total
from transactions_fee_per_period
$$ language sql stable;
