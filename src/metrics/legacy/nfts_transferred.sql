create or replace function ecosystem.nfts_transferred(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with nfts_transferred_per_period as (
  select date_trunc(period, upper(timestamp_range)::timestamp9::timestamp) as period_start_timestamp,
  count(*) as total
  from nft_history
  where upper(timestamp_range) between start_timestamp and end_timestamp
  and lower(timestamp_range) != created_timestamp -- ignore minted NFTs
  group by 1
  order by 1 desc
)

select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
total

from nfts_transferred_per_period

$$;
