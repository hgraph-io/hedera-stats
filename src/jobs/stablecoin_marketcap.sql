-----------------------
-- stablecoin marketcap
-----------------------
create or replace procedure ecosystem.load_stablecoin_marketcap()
as $$

  with defillama as (
    select
        (jsonb_array_elements(content)->>'date')::numeric as date_sec,
        (jsonb_array_elements(content)->'totalCirculating'->> 'peggedUSD')::numeric as marketcap
    from (
      select content::jsonb as content
      from http_get('https://stablecoins.llama.fi/stablecoincharts/Hedera')
    )
  ),
  transformed as (
    select
      int8range(
        (to_timestamp(date_sec) - '1 day'::interval)::timestamp9::bigint,
        (to_timestamp(date_sec))::timestamp9::bigint
      ) as timestamp_range,
    marketcap
    from defillama
  )

  insert into ecosystem.metric (name, period, timestamp_range, total)
  select 'stablecoin_marketcap', 'day', timestamp_range, marketcap
  from transformed
  on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

$$ language sql;
