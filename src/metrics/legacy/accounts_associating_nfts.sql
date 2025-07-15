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
all_rows as (
  select period_start_timestamp
  from generate_series(
    date_trunc(period, start_timestamp::timestamp9::timestamp),
    date_trunc(period, end_timestamp::timestamp9::timestamp),
    '1 hour'::interval
  ) as period_start_timestamp
),
accounts_associating_nfts as (
  select
    date_trunc(period, created_timestamp) as period_start_timestamp,
    count(distinct account_id) as total
  from all_nft_token_accounts
  group by 1
),

result_set as (
  select
    period_start_timestamp,
    coalesce(accounts_associating_nfts.total, 0) as total
  from accounts_associating_nfts
  full outer join all_rows using (period_start_timestamp)
)

select
  int8range(
    period_start_timestamp::timestamp9::bigint,
    -- (period_start_timestamp + ('1 ' || period)::interval)::timestamp9::bigint
    (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
  ),
  result_set.total
from result_set

$$;
