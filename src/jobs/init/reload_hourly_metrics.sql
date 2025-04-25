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
        'network_fee'
        'account_growth',
        'network_tps'
    ];
    metric_name text;

    clock_start timestamp := clock_timestamp();
    metric_loop_time timestamp;

    end_timestamp bigint := now()::timestamp9::date::timestamp9::bigint;
    start_timestamp bigint := (end_timestamp::timestamp9 - '1 hour'::interval)::bigint;

    -- result_set ecosystem.metric;
    genesis bigint := (select consensus_timestamp::timestamp9::date::timestamp9::bigint as start_timestamp from transaction order by consensus_timestamp asc limit 1);


begin
  set time zone 'utc';

  while start_timestamp >= genesis loop

    foreach metric_name in array metrics loop
      -- set the start period
      metric_loop_time := clock_timestamp();
      raise notice 'loading %', metric_name;
      raise notice 'start: %, end: %', start_timestamp::timestamp9, end_timestamp::timestamp9;

      execute format(
        $sql$
          insert into ecosystem.metric (name, period, timestamp_range, total)
          select %L as name,
                 'hour' as period,
                 int8range,
                 total
          from ecosystem.%I('hour', %s, %s)
          where upper(int8range) is not null
          on conflict (name, period, timestamp_range)
          do update set total = excluded.total
        $sql$, metric_name, metric_name, start_timestamp, end_timestamp);

		-- raise notice 'results: %', result_set;

      commit;

      -- set the next period
      end_timestamp := start_timestamp;
      start_timestamp := (end_timestamp::timestamp9 - '1 hour'::interval)::bigint;

    end loop;
  end loop;
  raise notice 'total elapsed time %', clock_timestamp() - clock_start;
end;
$$;
