-- daily job
create or replace procedure ecosystem.load_daily_metrics()
language plpgsql
as $$

declare

    metrics text[] := array [
      'network_fee',
      'network_tps'
    ];
    metric_name text;

    total_time timestamp;
    metric_loop_time timestamp;

    end_timestamp_bigint bigint;
    last_upper_bound bigint;
begin
    set time zone 'utc';
    total_time := clock_timestamp();

    -- Truncate current time to day so we don't include a partial day
    end_timestamp_bigint := date_trunc('day', now())::timestamp9::bigint;

    raise notice 'loading daily metrics up to % (utc)', (end_timestamp_bigint)::timestamp9;

    foreach metric_name in array metrics loop
        metric_loop_time := clock_timestamp();

        select coalesce(max(upper(timestamp_range)), 0)
          into last_upper_bound
          from ecosystem.metric
         where period = 'day'
           and name = metric_name;

        raise notice 'metric: %, last_upper_bound: % => % (utc)',
                     metric_name,
                     last_upper_bound,
                     (last_upper_bound)::timestamp9;

        if last_upper_bound >= end_timestamp_bigint then
            raise notice 'no new full days to insert for metric %', metric_name;
        else
            execute format($sql$
                insert into ecosystem.metric (name, period, timestamp_range, total)
                select %L as name,
                       'day' as period,
                       int8range,
                       total
                  from ecosystem.%I('day', %s, %s)
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
