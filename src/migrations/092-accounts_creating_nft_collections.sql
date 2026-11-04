-- 092-accounts_creating_nft_collections.sql — accounts_creating_nft_collections metric: distinct treasury accounts creating NFT collections per period.
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

CREATE OR REPLACE FUNCTION ecosystem.accounts_creating_nft_collections(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

with distinct_treasury_account as (
	select date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
	count(distinct treasury_account_id) as total
	from token
	where created_timestamp between start_timestamp and end_timestamp
	and type = 'NON_FUNGIBLE_UNIQUE'
	group  by 1
	order by 1 desc
)
select
int8range(
	period_start_timestamp::timestamp9::bigint,
	(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
total

from distinct_treasury_account

$$;

COMMIT;
