create or replace function ecosystem.accounts_associating_nfts(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

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
