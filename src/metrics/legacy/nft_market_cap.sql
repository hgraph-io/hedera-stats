create or replace function ecosystem.nft_market_cap(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with latest_sale_per_nft as (
  select distinct on (token_id, serial_number) *
  from nft_history
  where upper(timestamp_range) between start_timestamp and end_timestamp
  order by token_id, serial_number, upper(timestamp_range) desc
  ), nft_hbar_transfers as (
  select *
  from latest_sale_per_nft as ls
  left join crypto_transfer as ct
  on ct.consensus_timestamp = upper(ls.timestamp_range)
  where ct.amount > 0
  ), total_hbar as (
  select
  date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
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
