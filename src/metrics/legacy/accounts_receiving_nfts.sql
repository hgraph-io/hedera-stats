create or replace function ecosystem.accounts_receiving_nfts(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with nfts_received as (
  (
    select lower(timestamp_range) as consensus_timestamp,
    account_id
    from nft_history
    where lower(timestamp_range) between start_timestamp and end_timestamp
  )
  union all
  (
    select lower(timestamp_range) as consensus_timestamp,
    account_id
    from nft
    where lower(timestamp_range) between start_timestamp and end_timestamp
  )
),
nfts_received_per_period as (
  select date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count(distinct account_id) as total
  from nfts_received
  group by 1
  order by 1 desc
)

select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
total
from nfts_received_per_period

$$;
