create or replace procedure ecosystem.load_init_metrics()
language plpgsql
as $$

declare
    periods text[] := array['day', 'week', 'month', 'quarter', 'year', 'century'];
    current_period text;

    -- trimmed to the five requested metrics
    metrics text[] := array[
        'total_accounts',
        'total_ecdsa_accounts',
        'total_ed25519_accounts',
        'active_ed25519_accounts'
    ];
    metric text;

    total_time timestamp;
    metric_loop_time timestamp;
    period_loop_time timestamp;

begin
    set time zone 'UTC';
    total_time := clock_timestamp();

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
                    from ecosystem.%s(%L::text, %L::bigint) where upper(int8range) is not null
                    on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total'
                    , metric, current_period, metric, current_period, starting_timestamp);
                commit;

                raise notice E'\n metric_loop_time: %,\n period_loop_time: %,\n total_time: % \n'
                , clock_timestamp() - metric_loop_time, clock_timestamp() - period_loop_time, clock_timestamp() - total_time;
            end;
        end loop;
    end loop;
end;
$$;
