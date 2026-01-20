create or replace function ecosystem.avg_gas_used(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem.metric_total
as $$
with gas_transactions as (
    select
        cr.consensus_timestamp,
        cr.gas_used
    from contract_result cr
    where cr.consensus_timestamp between start_timestamp and end_timestamp
    and cr.transaction_result = 22 -- success result
    and cr.gas_used is not null
    and cr.gas_used > 0
),
gas_per_period as (
    select
        date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
        avg(gas_used)::bigint as total
    from gas_transactions
    group by 1
    order by 1 desc
)
select
    int8range(
        period_start_timestamp::timestamp9::bigint,
        (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
    ),
    total
from gas_per_period
$$ language sql stable;
