create or replace function ecosystem.accounts_creating_nft_collections(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

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
