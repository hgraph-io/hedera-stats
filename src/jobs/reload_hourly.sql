-- initial load or reload of hourly metrics
create or replace procedure ecosystem.reload_hourly_metrics()
language plpgsql
as $$

declare

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
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'active_accounts',
        'network_fee',
        'account_growth',
        'network_tps',
        'avg_usd_conversion'
    ];
    metric_name text;

    total_time timestamp;
    metric_loop_time timestamp;

    end_timestamp_bigint bigint;
    genesis bigint := (select consensus_timestamp::timestamp9::date::timestamp9::bigint as start_timestamp from transaction order by consensus_timestamp asc limit 1);


begin
    set time zone 'utc';
    total_time := clock_timestamp();

    -- Truncate current time to hour so we don't include a partial hour
    end_timestamp_bigint := date_trunc('hour', now())::timestamp9::bigint;

    raise notice 'loading hourly metrics up to % (utc)', (end_timestamp_bigint)::timestamp9;

    foreach metric_name in array metrics loop
        metric_loop_time := clock_timestamp();

          execute format($sql$
              insert into ecosystem.metric (name, period, timestamp_range, total)
              select %L as name,
                     'hour' as period,
                     int8range,
                     total
                from ecosystem.%I('hour', %s, %s)
              on conflict (name, period, timestamp_range)
              do update
                set total = excluded.total
          $sql$, metric_name, metric_name, genesis, end_timestamp_bigint);

          commit;

        raise notice e'\n metric_name: %, \n metric_loop_time: %,\n total_time: % \n',
                     metric_name,
                     clock_timestamp() - metric_loop_time,
                     clock_timestamp() - total_time;
    end loop;

end;
$$;
