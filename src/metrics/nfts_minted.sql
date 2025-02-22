create or replace function ecosystem.nfts_minted(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with all_entries as (
  select token_id, serial_number, created_timestamp from nft
  union all
  select token_id, serial_number, created_timestamp from nft_history
),
nfts_minted_per_period as (
  select date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count( distinct(token_id, serial_number)) as total
  from all_entries
  where created_timestamp between start_timestamp and end_timestamp
  group by 1
  order by 1 asc
)

select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
total

from nfts_minted_per_period

$$;
