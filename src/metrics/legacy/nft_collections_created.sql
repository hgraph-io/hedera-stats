create or replace function ecosystem.nft_collections_created(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default CURRENT_TIMESTAMP::timestamp9::bigint
)
returns setof ecosystem . metric_total
language sql stable
as $$

with nft_collection as (
  select *
  from token
  where created_timestamp between start_timestamp and end_timestamp
  and type = 'NON_FUNGIBLE_UNIQUE'
  group  by 1
  order by 1 desc
),
created_nft_collection as (
  select date_trunc(period, nft_collection.created_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count(distinct nft_collection.token_id) as total
  from nft_collection
  group by 1
)

select
int8range(
  period_start_timestamp::timestamp9::bigint,
  (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
),
created_nft_collection.total

from created_nft_collection

$$;
