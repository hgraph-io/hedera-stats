----------------------------------------------------
-- LOAD METRICS BETA / HEDERASTATS.com / HGRAPH.com
-- Automates upsert of metrics into ecosystem.metric
----------------------------------------------------

-- NOTE: This procedure handles NFT related metrics (previously in load_metrics.sql).

create or replace procedure ecosystem.load_metrics_beta(
    in _period text default 'century'  -- keep flexibility if you ever want day/week/etc.
)
language plpgsql
as $$
begin
    -- total_nfts
    raise notice 'metric: total_nfts, period: %', _period;
    insert into ecosystem.metric (name, period, timestamp_range, total)
    select 'total_nfts', _period, int8range, total
      from ecosystem.current_total_nfts()
    on conflict (name, period, timestamp_range) do
        update set total = excluded.total;

    -- nft_holders
    raise notice 'metric: nft_holders, period: %', _period;
    insert into ecosystem.metric (name, period, timestamp_range, total)
    select 'nft_holders', _period, int8range, total
      from ecosystem.current_nft_holders()
    on conflict (name, period, timestamp_range) do
        update set total = excluded.total;

    -- nft_market_cap
    raise notice 'metric: nft_market_cap, period: %', _period;
    insert into ecosystem.metric (name, period, timestamp_range, total)
    select 'nft_market_cap', _period, int8range, total
      from ecosystem.current_nft_market_cap()
    on conflict (name, period, timestamp_range) do
        update set total = excluded.total;
end;
$$;
