create or replace procedure ecosystem.load_metrics()
language plpgsql
as $$

declare
    periods text[] := array['day', 'week', 'month', 'quarter', 'year', 'century'];
    current_period text;

    metrics text[] := array [
        'accounts_associating_nfts',
        'accounts_receiving_nfts',
        'accounts_sending_nfts',
        'accounts_minting_nfts',
        'accounts_creating_nft_collections',
        'active_nft_accounts',
        'active_nft_builder_accounts',
        'nft_collections_created',
        'nfts_minted',
        'nfts_transferred',
        'nft_sales_volume',
        -- network_tvl and stablecoin_marketcap raw data are updated in DefiLlama every day at midnight
        'network_tvl',
        'stablecoin_marketcap',
        'avg_usd_conversion'
    ];
    metric text;

    total_time timestamp;
    metric_loop_time timestamp;
    period_loop_time timestamp;

begin
    set time zone 'UTC';
    total_time := clock_timestamp();

    -- Insert current totals for 3 metrics
    insert into ecosystem.metric (name, period, timestamp_range, total)
        select 'total_nfts' as name, 'century' as period, int8range as timestamp_range, total
        from ecosystem.current_total_nfts() on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

    insert into ecosystem.metric (name, period, timestamp_range, total)
        select 'nft_holders' as name, 'century' as period, int8range as timestamp_range, total
        from ecosystem.current_nft_holders() on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

    insert into ecosystem.metric (name, period, timestamp_range, total)
        select 'nft_market_cap' as name, 'century' as period, int8range as timestamp_range, total
        from ecosystem.current_nft_market_cap() on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

    -- Metrics for different time intervals
    foreach metric in array metrics loop
        metric_loop_time := clock_timestamp();

        foreach current_period in array periods loop
            period_loop_time := clock_timestamp();

            raise notice 'metric: %, period: %', metric, current_period;
            declare
                starting_timestamp bigint := 0;
            begin
                execute format ('
                    select coalesce(max(upper(timestamp_range)), 0::bigint)
                    from ecosystem.metric
                    where period = %L
                    and name = %L
                    ', current_period, metric)
                    into starting_timestamp;

                raise notice 'metric: %, starting_timestamp: %', metric, starting_timestamp;

                execute format('
                    insert into ecosystem.metric (name, period, timestamp_range, total)
                    select %L as name, %L as period, int8range as timestamp_range, total
                    from ecosystem.%s(%L::text, %L::bigint) on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total'
                    , metric, current_period, metric, current_period, starting_timestamp);
                commit;

                raise notice E'\n metric_loop_time: %,\n period_loop_time: %,\n total_time: % \n'
                , clock_timestamp() - metric_loop_time, clock_timestamp() - period_loop_time, clock_timestamp() - total_time;
            end;
        end loop;
    end loop;
end;
$$;
