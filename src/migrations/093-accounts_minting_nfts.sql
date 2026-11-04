-- 093-accounts_minting_nfts.sql — accounts_minting_nfts metric: distinct accounts minting NFTs per period.
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

CREATE OR REPLACE FUNCTION ecosystem.accounts_minting_nfts(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

with all_entries as (
	select created_timestamp, account_id from nft
	where created_timestamp between start_timestamp and end_timestamp

	union all

	select created_timestamp, account_id from nft_history
	where created_timestamp between start_timestamp and end_timestamp
),
accounts_minting_nfts as (
	select date_trunc(period, created_timestamp::timestamp9::timestamp) as period_start_timestamp,
	count(distinct account_id) as total
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

from accounts_minting_nfts

$$;

COMMIT;
