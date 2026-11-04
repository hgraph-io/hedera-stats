-- 102-nfts_transferred.sql — nfts_transferred metric: NFT transfers per period.
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

CREATE OR REPLACE FUNCTION ecosystem.nfts_transferred(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

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

COMMIT;
