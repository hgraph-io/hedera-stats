CREATE OR REPLACE PROCEDURE ecosystem.load_metrics_init_2()
LANGUAGE plpgsql
AS $$
DECLARE
    periods CONSTANT text[] := array['hour', 'day', 'week', 'month', 'quarter', 'year'];
    metrics CONSTANT text[] := array[
        'total_hcs_transactions',
        'total_transactions',
        'new_hcs_transactions',
        'new_transactions'
    ];
    current_period TEXT;
    metric TEXT;

    total_time TIMESTAMP;
    metric_loop_time TIMESTAMP;
    period_loop_time TIMESTAMP;

    starting_timestamp BIGINT := 0;
    end_timestamp_bigint BIGINT;
    processed_metrics INT := 0;
    errors JSONB := '[]'::jsonb;
    dynamic_sql TEXT;
    rows_affected INT;
BEGIN
    SET TIME ZONE 'UTC';
    total_time := clock_timestamp();

    -- Loop through each metric and period
    FOREACH metric IN ARRAY metrics LOOP
        metric_loop_time := clock_timestamp();

        FOREACH current_period IN ARRAY periods LOOP
            period_loop_time := clock_timestamp();

            -- Truncate now() to correct period for end bound
            end_timestamp_bigint := date_trunc(current_period, now())::timestamp9::bigint;

            -- Try-catch to isolate failures to each metric/period, and continue if one fails
            BEGIN
                RAISE INFO 'Processing metric: %, period: %', metric, current_period;

                -- Compute the most recent known interval for this metric/period
                EXECUTE format (
                    'SELECT coalesce(max(upper(timestamp_range)), 0::bigint)
                     FROM ecosystem.metric
                     WHERE period = %L AND name = %L',
                    current_period, metric
                ) INTO starting_timestamp;

                RAISE INFO '  -> Starting at timestamp: %', starting_timestamp;
                RAISE INFO '  -> Ending at timestamp: %', end_timestamp_bigint;

                -- Build dynamic SQL
                dynamic_sql := format(
                    'INSERT INTO ecosystem.metric (name, period, timestamp_range, total)
                     SELECT %L AS name, %L AS period, int8range AS timestamp_range, total
                     FROM ecosystem.%I(%L::text, %L::bigint, %L::bigint)
                     WHERE upper(int8range) IS NOT NULL
                     ON CONFLICT (name, period, timestamp_range) DO UPDATE SET total = EXCLUDED.total',
                    metric, current_period, metric, current_period, starting_timestamp, end_timestamp_bigint
                );
                RAISE INFO '  -> Dynamic SQL: %', dynamic_sql;

                EXECUTE dynamic_sql;
                GET DIAGNOSTICS rows_affected = ROW_COUNT;
                RAISE INFO '    [SQL] Rows affected: %', rows_affected;

                processed_metrics := processed_metrics + 1;

                RAISE INFO '    [Done] metric %, period %, elapsed: %',
                    metric, current_period, clock_timestamp() - period_loop_time;

            EXCEPTION WHEN OTHERS THEN
                -- Capture error for this metric/period, log it, continue loop
                errors := errors || jsonb_build_object(
                    'metric', metric,
                    'period', current_period,
                    'error', sqlerrm,
                    'sql', dynamic_sql,
                    'at', now()
                );
                RAISE WARNING 'Failed to process metric %, period %: % SQL: %', 
                    metric, current_period, sqlerrm, dynamic_sql;
                CONTINUE;  -- Proceed to next metric/period
            END;
        END LOOP;
    END LOOP;

    -- Log summary
    RAISE INFO 'Load_metrics summary: %', jsonb_build_object(
        'metrics_processed', processed_metrics,
        'errors', errors,
        'ran_at_utc', now(),
        'elapsed_seconds', extract(epoch FROM (clock_timestamp() - total_time))
    );
END;
$$;
