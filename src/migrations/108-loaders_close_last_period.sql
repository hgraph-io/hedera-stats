-- 108-loaders_close_last_period.sql — stop the scheduled loaders running one period behind.
--
-- Most metric functions end each row's range at lead(period_start): the start of the
-- next row. The newest row has no next row, so its upper bound is NULL, and the
-- loaders dropped it (`where upper(int8range) is not null`). Every series therefore
-- trailed by one complete period: yesterday's day row arrived a day late, last
-- week's a week late. 49 functions do this; the 19 that coalesce lead() with
-- end_timestamp were already current.
--
-- Fixing it here instead of in 49 function bodies: the loader already knows the
-- exact boundary it asked for (end_timestamp_bigint = date_trunc(period, now())),
-- so a NULL upper becomes that boundary. A row starting at or after the boundary
-- (a transaction landing exactly on it, since the functions use BETWEEN) is still
-- skipped, as the incomplete current period.
--
-- Self-healing: each loader resumes from max(upper), which is the start of the
-- period that was being dropped, so the next run of each loader stores it. No
-- backfill needed.
--
-- A sparse metric whose newest row is older than the last complete period gets a
-- range spanning to the boundary, which is what lead() already produces for gaps
-- between rows.
--
-- Each procedure is its latest migration verbatim (018, 016, 015, 106, 086) except
-- that one statement.

BEGIN;

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

                raise info '  -> Starting at timestamp: % (%)', starting_timestamp, starting_timestamp::timestamp9::timestamp;

                -- Dynamically call the correct function, safely, for this metric/period/timestamp
                execute format(
                    'insert into ecosystem.metric (name, period, timestamp_range, total)
                     select %1$L as name, %2$L as period,
                            int8range(lower(int8range), coalesce(upper(int8range), %4$L::bigint)) as timestamp_range, total
                     from ecosystem.%1$I(%2$L::text, %3$L::bigint, %4$L::bigint)
                     where lower(int8range) < %4$L::bigint
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, starting_timestamp, end_timestamp_bigint
                );

                processed_metrics := processed_metrics + 1;

                -- Retention: delete minute data older than 72 hours
                DELETE FROM ecosystem.metric
                WHERE name = 'avg_usd_conversion'
                  AND period = 'minute'
                  AND upper(timestamp_range) < (date_trunc('minute', now() - interval '72 hours'))::timestamp9::bigint;

                raise info '    [Done] metric %, period %, elapsed: %',
                    metric, current_period, clock_timestamp() - period_loop_time;

            exception when others then
                -- Capture error for this metric/period, log it, continue loop
                errors := errors || jsonb_build_object(
                    'metric', metric,
                    'period', current_period,
                    'error', sqlerrm,
                    'sqlstate', SQLSTATE,
                    'at', now()
                );
                raise warning 'Failed to process metric %, period %: % (SQLSTATE: %)', metric, current_period, sqlerrm, SQLSTATE;
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

create or replace procedure ecosystem.load_metrics_hour()
language plpgsql
as $$
declare
    periods constant text[] := array['hour'];      -- Hour (the period for this job)
    metrics constant text[] := array[
        'avg_usd_conversion',
        'hbar_total_released',
        'hbar_market_cap',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'avg_gas_used',
        'avg_gas_used_contract_call',
        'avg_gas_used_ethereum_tx',
        'avg_gas_used_contract_create',
        'active_accounts',
        'active_ecdsa_accounts',
        'active_ed25519_accounts',
        'network_fee',
        'avg_network_fee',
        'network_tps',
        'new_accounts',
        'new_ecdsa_accounts',
        'new_ecdsa_accounts_real_evm',
        'new_ed25519_accounts',
        'new_smart_contracts',
        'new_transactions',
        'new_hcs_transactions',
        'new_hfs_transactions',
        'new_hscs_transactions',
        'new_hts_transactions',
        'new_crypto_transactions',
        'new_other_transactions',
        'nft_collections_created'
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

    -- Always truncate to the start of the current hour in UTC
    end_timestamp_bigint := date_trunc('hour', now())::timestamp9::bigint;

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
                     select %1$L as name, %2$L as period,
                            int8range(lower(int8range), coalesce(upper(int8range), %4$L::bigint)) as timestamp_range, total
                     from ecosystem.%1$I(%2$L::text, %3$L::bigint, %4$L::bigint)
                     where lower(int8range) < %4$L::bigint
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, starting_timestamp, end_timestamp_bigint
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

create or replace procedure ecosystem.load_metrics_day()
language plpgsql
as $$
declare
    periods constant text[] := array['day'];      -- Day (the period for this job)
    metrics constant text[] := array[
        'total_accounts',
        'total_ecdsa_accounts',
        'total_ed25519_accounts',
        'total_smart_contracts',
        'total_erc1155_accounts',
        'total_erc20_accounts',
        'total_erc721_accounts',
        'total_erc1400_accounts',
        'total_erc3643_accounts',
        'hbar_total_released',
        'avg_usd_conversion',
        'hbar_market_cap',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'avg_gas_used',
        'avg_gas_used_contract_call',
        'avg_gas_used_ethereum_tx',
        'avg_gas_used_contract_create',
        'active_accounts',
        'active_ecdsa_accounts',
        'active_ed25519_accounts',
        'network_fee',
        'avg_network_fee',
        'network_tps',
        'new_accounts',
        'new_ecdsa_accounts',
        'new_ecdsa_accounts_real_evm',
        'new_ed25519_accounts',
        'new_smart_contracts',
        'new_transactions',
        'new_hcs_transactions',
        'new_hfs_transactions',
        'new_hscs_transactions',
        'new_hts_transactions',
        'new_crypto_transactions',
        'new_other_transactions',
        'nft_collections_created',
        'total_transactions', -- light
        'total_hcs_transactions', -- light
        'total_crypto_transactions', -- light
        'total_hfs_transactions',
        'total_hscs_transactions',
        'total_hts_transactions',
        'total_other_transactions'
    ];                                            -- Metrics (functions for this job)
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

    -- Always truncate to the start of the current day in UTC
    end_timestamp_bigint := date_trunc('day', now())::timestamp9::bigint;

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
                     select %1$L as name, %2$L as period,
                            int8range(lower(int8range), coalesce(upper(int8range), %4$L::bigint)) as timestamp_range, total
                     from ecosystem.%1$I(%2$L::text, %3$L::bigint, %4$L::bigint)
                     where lower(int8range) < %4$L::bigint
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, starting_timestamp, end_timestamp_bigint
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
        'total_erc20_accounts',
        'total_erc721_accounts',
        'total_erc1400_accounts',
        'total_erc3643_accounts',
        'hbar_total_released',
        'hbar_market_cap',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'avg_gas_used',
        'avg_gas_used_contract_call',
        'avg_gas_used_ethereum_tx',
        'avg_usd_conversion',
        'avg_gas_used_contract_create',
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
        'nft_collections_created',
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
                     select %1$L as name, %2$L as period,
                            int8range(lower(int8range), coalesce(upper(int8range), %4$L::bigint)) as timestamp_range, total
                     from ecosystem.%1$I(%2$L::text, %3$L::bigint, %4$L::bigint)
                     where lower(int8range) < %4$L::bigint
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, starting_timestamp, end_timestamp_bigint
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

create or replace procedure ecosystem.load_metrics_month()
language plpgsql
as $$
declare
    periods constant text[] := array['month'];      -- Month (the period for this job)
    metrics constant text[] := array[
        'total_accounts',
        'total_ecdsa_accounts',
        'total_ed25519_accounts',
        'total_smart_contracts',
        'total_erc1155_accounts',
        'total_erc20_accounts',
        'total_erc721_accounts',
        'total_erc1400_accounts',
        'total_erc3643_accounts',
        'hbar_total_released',
        'hbar_market_cap',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'avg_gas_used',
        'avg_gas_used_contract_call',
        'avg_gas_used_ethereum_tx',
        'avg_usd_conversion',
        'avg_gas_used_contract_create',
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
        'nft_collections_created',
        'total_transactions', -- light
        'total_hcs_transactions', -- light
        'total_crypto_transactions', -- light
        'total_hfs_transactions',
        'total_hscs_transactions',
        'total_hts_transactions',
        'total_other_transactions',
        'network_tps'
    ];                                              -- Metrics (functions for this job)
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

    -- Always truncate to the start of the current month in UTC
    end_timestamp_bigint := date_trunc('month', now())::timestamp9::bigint;

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
                     select %1$L as name, %2$L as period,
                            int8range(lower(int8range), coalesce(upper(int8range), %4$L::bigint)) as timestamp_range, total
                     from ecosystem.%1$I(%2$L::text, %3$L::bigint, %4$L::bigint)
                     where lower(int8range) < %4$L::bigint
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, starting_timestamp, end_timestamp_bigint
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

create or replace procedure ecosystem.load_metrics_quarter()
language plpgsql
as $$
declare
    periods constant text[] := array['quarter'];      -- Quarter (the period for this job)
    metrics constant text[] := array[
        'total_accounts',
        'total_ecdsa_accounts',
        'total_ed25519_accounts',
        'total_smart_contracts',
        'total_erc1155_accounts',
        'total_erc20_accounts',
        'total_erc721_accounts',
        'total_erc1400_accounts',
        'total_erc3643_accounts',
        'hbar_total_released',
        'hbar_market_cap',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'avg_gas_used',
        'avg_gas_used_contract_call',
        'avg_gas_used_ethereum_tx',
        'avg_gas_used_contract_create',
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
        'nft_collections_created',
        'total_transactions', -- light
        'total_hcs_transactions', -- light
        'total_crypto_transactions', -- light
        'total_hfs_transactions',
        'total_hscs_transactions',
        'total_hts_transactions',
        'total_other_transactions',
        'network_tps'
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

begin
    set time zone 'UTC';
    total_time := clock_timestamp();
    -- Always truncate to the start of the current quarter in UTC
    end_timestamp_bigint := date_trunc('quarter', now())::timestamp9::bigint;

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
                     select %1$L as name, %2$L as period,
                            int8range(lower(int8range), coalesce(upper(int8range), %4$L::bigint)) as timestamp_range, total
                     from ecosystem.%1$I(%2$L::text, %3$L::bigint, %4$L::bigint)
                     where lower(int8range) < %4$L::bigint
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, starting_timestamp, end_timestamp_bigint
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

create or replace procedure ecosystem.load_metrics_year()
language plpgsql
as $$
declare
    periods constant text[] := array['year'];      -- Year (the period for this job)
    metrics constant text[] := array[
        'total_accounts',
        'total_ecdsa_accounts',
        'total_ed25519_accounts',
        'total_smart_contracts',
        'total_erc1155_accounts',
        'total_erc20_accounts',
        'total_erc721_accounts',
        'total_erc1400_accounts',
        'total_erc3643_accounts',
        'hbar_total_released',
        'hbar_market_cap',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'avg_gas_used',
        'avg_gas_used_contract_call',
        'avg_gas_used_ethereum_tx',
        'avg_gas_used_contract_create',
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
        'nft_collections_created',
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

    -- Always truncate to the start of the current year in UTC
    end_timestamp_bigint := date_trunc('year', now())::timestamp9::bigint;

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
                     select %1$L as name, %2$L as period,
                            int8range(lower(int8range), coalesce(upper(int8range), %4$L::bigint)) as timestamp_range, total
                     from ecosystem.%1$I(%2$L::text, %3$L::bigint, %4$L::bigint)
                     where lower(int8range) < %4$L::bigint
                     on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total',
                    metric, current_period, starting_timestamp, end_timestamp_bigint
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

COMMIT;
