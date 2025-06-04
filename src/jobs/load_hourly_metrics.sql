-- hourly job
create or replace procedure ecosystem.load_hourly_metrics()
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
        'active_ecdsa_accounts',
        'active_ed25519_accounts',
        'network_fee',
        'account_growth',
        'network_tps',
        'new_accounts'
    ];
    metric_name text;

    total_time timestamp;
    metric_loop_time timestamp;

    end_timestamp_bigint bigint;
    last_upper_bound bigint;
begin
    set time zone 'utc';
    total_time := clock_timestamp();

    -- Truncate current time to hour so we don't include a partial hour
    end_timestamp_bigint := date_trunc('hour', now())::timestamp9::bigint;

    raise notice 'loading hourly metrics up to % (utc)', (end_timestamp_bigint)::timestamp9;

    foreach metric_name in array metrics loop
        metric_loop_time := clock_timestamp();

        select coalesce(max(upper(timestamp_range)), 0)
          into last_upper_bound
          from ecosystem.metric
         where period = 'hour'
           and name = metric_name;

        raise notice 'metric: %, last_upper_bound: % => % (utc)',
                     metric_name,
                     last_upper_bound,
                     (last_upper_bound)::timestamp9;

        if last_upper_bound >= end_timestamp_bigint then
            raise notice 'no new full hours to insert for metric %', metric_name;
        else
            execute format($sql$
                insert into ecosystem.metric (name, period, timestamp_range, total)
                select %L as name,
                       'hour' as period,
                       int8range,
                       total
                  from ecosystem.%I('hour', %s, %s)
                  where upper(int8range) is not null
                on conflict (name, period, timestamp_range)
                do update
                  set total = excluded.total
            $sql$, metric_name, metric_name, last_upper_bound, end_timestamp_bigint);

            commit;
        end if;

        raise notice e'\n metric_loop_time: %,\n total_time: % \n',
                     clock_timestamp() - metric_loop_time,
                     clock_timestamp() - total_time;
    end loop;

end;
$$;
