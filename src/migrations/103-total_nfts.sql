-- 103-total_nfts.sql — total_nfts metric: non-deleted NFTs per period, from nft and nft_history
-- ownership ranges.
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

CREATE OR REPLACE FUNCTION ecosystem.total_nfts(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

with all_entries as (
  select
  token_id,
  serial_number,
  lower(timestamp_range) as start_timestamp,
  9223372036854775807 as end_timestamp
  from nft
  where deleted is false

  union all

  -- nft_history.deleted is always false
  select
  token_id,
  serial_number,
  lower(timestamp_range) as start_timestamp,
  upper(timestamp_range) as end_timestamp
  from nft_history
),
active_nfts_per_period as (
  select date_trunc(period, end_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count( distinct(token_id, serial_number)) as total
  from all_entries
  where
  -- created before the period end and ended during or after the period
  all_entries.start_timestamp <= end_timestamp and all_entries.end_timestamp > start_timestamp
  group by 1
  order by 1 asc
)

select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
total

from active_nfts_per_period

$$;

COMMIT;
