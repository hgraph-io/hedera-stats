create or replace function ecosystem.current_total_nfts()
returns setof ecosystem . metric_total
language sql stable
as $$

select
int8range(0, CURRENT_TIMESTAMP::timestamp9::bigint) as timestamp_range,
(
  select count(distinct(token_id, serial_number))
  from nft
  where deleted is false
) as total

$$;
