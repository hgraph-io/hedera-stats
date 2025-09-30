----------------------------------------------------
-- LOAD METRICS MINUTE / HEDERASTATS.com / HGRAPH.com
-- Automates upsert of metrics into ecosystem.metric
----------------------------------------------------

create or replace procedure ecosystem.load_metrics_minute()
language plpgsql
as $$
declare
    periods constant text[] := array['minute'];      -- Minute (the period for this job)
    metrics constant text[] := array[
        'avg_usd_conversion'
    ];                                                -- Metrics (functions for this job)
    current_period text;
    metric text;

    total_time timestamp;
    metric_loop_time timestamp;
    period_loop_time timestamp;

    starting_timestamp bigint := 0;
    end_timestamp_bigint bigint;
    processed_metrics int := 0;
    errors jsonb := '[]'::jsonb;

    -- Retention window (hours)
    retention_hours constant integer := 72;

begin
    set time zone 'UTC';
    total_time := clock_timestamp();

    -- Always truncate to the start of the current minute in UTC
    end_timestamp_bigint := date_trunc('minute', now())::timestamp9::bigint;

    -- Loop through each metric and period
    foreach metric in array metrics loop
        metric_loop_time := clock_timestamp();

        foreach current_period in array periods loop
            period_loop_time := clock_timestamp();

            -- Try-catch to isolate failures to each metric/period, and continue if one fails
            begin
                raise info 'Processing metric: %, period: %', metric, current_period;

                -- Compute the most recent known interval for this metric/period
                execute format (
                    'select coalesce(max(upper(timestamp_range)), 0::bigint)
                     from ecosystem.metric
                     where period = %L and name = %L',
                    current_period, metric
                ) into starting_timestamp;

                raise info '  -> Starting at timestamp: %', starting_timestamp;

                -- Dynamically call the correct function, safely, for this metric/period/timestamp
                execute format(
                    'insert into ecosystem.metric (name, period, timestamp_range, total)
                     select %L as name, %L as period, int8range as timestamp_range, total
                     from ecosystem.%I(%L::text, %L::bigint, %L::bigint)
                     where upper(int8range) is not null
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, metric, current_period, starting_timestamp, end_timestamp_bigint
                );

                processed_metrics := processed_metrics + 1;

                -- Retention: delete minute data older than 72 hours
                DELETE FROM ecosystem.metric
                WHERE name = metric
                  AND period = current_period
                  AND upper(timestamp_range) < (date_trunc('minute', now() - interval '72 hours'))::timestamp9::bigint;

                raise info '    [Done] metric %, period %, elapsed: %',
                    metric, current_period, clock_timestamp() - period_loop_time;

            exception when others then
                -- Capture error for this metric/period, log it, continue loop
                errors := errors || jsonb_build_object(
                    'metric', metric,
                    'period', current_period,
                    'error', sqlerrm,
                    'at', now()
                );
                raise warning 'Failed to process metric %, period %: %', metric, current_period, sqlerrm;
                continue;  -- Proceed to next metric/period
            end;
        end loop;
    end loop;

    -- Log summary
    raise info 'Load_metrics_minute summary: %', jsonb_build_object(
        'metrics_processed', processed_metrics,
        'errors', errors,
        'ran_at_utc', now(),
        'elapsed_seconds', extract(epoch from (clock_timestamp() - total_time))
    );

end;
$$;