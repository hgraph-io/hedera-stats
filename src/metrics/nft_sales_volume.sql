create or replace function ecosystem.nft_sales_volume(
  granularity text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with all_nft_sales as (
  select *
  from nft_history
  where upper(timestamp_range) between start_timestamp and end_timestamp

  ), nft_hbar_transfers as (
  select amount, consensus_timestamp
  from all_nft_sales as ns
  left join crypto_transfer as ct
  on ct.consensus_timestamp = upper(ns.timestamp_range)
  where ct.amount > 0

  ), total_hbar as (
  select
  date_trunc(granularity, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
  sum(amount) as total
  from nft_hbar_transfers
  group by 1
  order by 1 asc
)


select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
total

from total_hbar

$$;
