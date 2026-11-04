-- 100-nft_sales_volume.sql — nft_sales_volume metric: HBAR volume of NFT sales per period.
--
-- Promoted from the publishers, where this function existed with no migration
-- (identical on the mainnet and testnet publishers unless noted below).
-- Body copied verbatim from the mainnet publisher's definition so that
-- applying it there is a no-op; behaviour changes belong in later migrations.
--
-- Reads mirror-node tables; on the publishers it is driven by the legacy
-- load_metrics / load_hourly_metrics loaders. Grants come from 082's
-- ALTER DEFAULT PRIVILEGES.

BEGIN;

CREATE OR REPLACE FUNCTION ecosystem.nft_sales_volume(granularity text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

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

COMMIT;
