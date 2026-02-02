----------------------------------------------------
-- LOAD METRICS WEEK / HEDERASTATS.com / HGRAPH.com
-- Automates upsert of metrics into ecosystem.metric
----------------------------------------------------

create or replace procedure ecosystem.load_metrics_week()
language plpgsql
as $$
declare
    periods constant text[] := array['week'];      -- Week (the period for this job)
    metrics constant text[] := array[
        'total_accounts',
        'total_ecdsa_accounts',
        'total_ed25519_accounts',
        'total_smart_contracts',
        'total_erc1155_accounts',
        'hbar_total_released',
        'hbar_market_cap',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'active_accounts',
        'active_ecdsa_accounts',
        'active_ed25519_accounts',
        'new_ecdsa_accounts_real_evm', -- need to add additional account metrics new/total
        'new_transactions',
        'new_hcs_transactions',
        'new_hfs_transactions',
        'new_hscs_transactions',
        'new_hts_transactions',
        'new_crypto_transactions',
        'new_other_transactions',
        'total_transactions', -- light
        'total_hcs_transactions', -- light
        'total_crypto_transactions', -- light
        'total_hfs_transactions',
        'total_hscs_transactions',
        'total_hts_transactions',
        'total_other_transactions',
        'network_tps'
    ];                                             -- Metrics (functions for this job)
    current_period text;
    metric text;

    total_time timestamp;
    metric_loop_time timestamp;
    period_loop_time timestamp;

    starting_timestamp bigint := 0;
    end_timestamp_bigint bigint;
    processed_metrics int := 0;
    errors jsonb := '[]'::jsonb;

begin
    set time zone 'UTC';
    total_time := clock_timestamp();

    -- Always truncate to the start of the current week in UTC
    end_timestamp_bigint := date_trunc('week', now())::timestamp9::bigint;

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
    raise info 'Load_metrics summary: %', jsonb_build_object(
        'metrics_processed', processed_metrics,
        'errors', errors,
        'ran_at_utc', now(),
        'elapsed_seconds', extract(epoch from (clock_timestamp() - total_time))
    );

end;
$$;
