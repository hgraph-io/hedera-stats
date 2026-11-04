-- 091-accounts_associating_nfts.sql — accounts_associating_nfts metric: distinct accounts associating an NFT
-- token (token_account created) per period.
--
-- Promoted from the publishers, where this function existed with no migration
-- (identical on the mainnet and testnet publishers unless noted below).
-- Body copied verbatim from the mainnet publisher's definition so that
-- applying it there is a no-op; behaviour changes belong in later migrations.
--
-- Mainnet's definition is adopted. The testnet publisher carried a variant with an
-- extra all_rows CTE that emitted a row for every hour in the window (including
-- empty ones); applying this migration there switches testnet to mainnet's output.
--
-- Reads mirror-node tables; on the publishers it is driven by the legacy
-- load_metrics / load_hourly_metrics loaders. Grants come from 082's
-- ALTER DEFAULT PRIVILEGES.

BEGIN;

CREATE OR REPLACE FUNCTION ecosystem.accounts_associating_nfts(period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT ((CURRENT_TIMESTAMP)::public.timestamp9)::bigint) RETURNS SETOF ecosystem.metric_total
    LANGUAGE sql STABLE
    AS $$

with all_nft_token_accounts as (
	select
	-- token account is created upon association of token
	token_account.created_timestamp::timestamp9::timestamp as created_timestamp,
	token_account.account_id
	from token_account
	inner join token on token_account.token_id = token.token_id
	where token_account.created_timestamp between start_timestamp and end_timestamp
	and token.type = 'NON_FUNGIBLE_UNIQUE'

),
accounts_associating_nfts as (
	select
	date_trunc(period, created_timestamp) as period_start_timestamp,
	count(distinct account_id) as total
	from all_nft_token_accounts
	group by 1
)

select
	int8range(
		period_start_timestamp::timestamp9::bigint,
		(lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
	),
	accounts_associating_nfts.total
from accounts_associating_nfts

$$;

COMMIT;
