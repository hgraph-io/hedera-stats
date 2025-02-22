create or replace function ecosystem.current_nft_holders()
returns setof ecosystem . metric_total
language sql stable
as $$

select
int8range(0, CURRENT_TIMESTAMP::timestamp9::bigint),
(
  select count(distinct account_id)
  from nft
  where deleted is false
) as total

$$;
