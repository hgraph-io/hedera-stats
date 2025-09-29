# Plan — Add `minute` Period to `avg_usd_conversion`

**Status: COMPLETED**

## Objective

Add a **`minute`** period for `avg_usd_conversion`, loaded **every minute** via `pg_cron`. Keep only the **last 72 hours** of `minute` rows, trimming older data on each run. Provide a lightweight backfill that seeds up to 72 hours of history using the existing init pattern.

---

## Changes Overview

- New procedure: `src/jobs/load_metrics_minute.sql`
- Cron entry: `src/jobs/pg_cron_metrics.sql` (every 1 minute)
- Init backfill script (copy of hour version, tuned for minute): `src/jobs/init/avg_usd_conversion_minute.sql`
- No schema changes required (uses existing `ecosystem.metric` uniqueness)

---

## Implementation Steps

1. **Deploy procedure** - Create `src/jobs/load_metrics_minute.sql`
2. **Test manually** - Run `CALL ecosystem.load_metrics_minute()` to verify
3. **Backfill if needed** - Execute init script for historical data
4. **Schedule cron** - Add entry to `pg_cron_metrics.sql`
5. **Validate** - Run validation queries to confirm data

---

## 1) Procedure — `src/jobs/load_metrics_minute.sql`

```sql
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
```

### Notes

- Uses the existing `ecosystem.avg_usd_conversion(period, start_ns, end_ns)` which already maps third-party API intervals for `'minute'` and caps each call at **100 candles** (OKX's limit).
- Retention delete runs **inside** the procedure on every execution and only affects `name='avg_usd_conversion' AND period='minute'`.
- Idempotent due to `ON CONFLICT … DO UPDATE`.
- Structure follows the exact pattern of `load_metrics_hour.sql` for consistency.
- Consider adding index on `(name, period, upper(timestamp_range))` if retention DELETE performance becomes an issue.
- Backfill uses 100-minute chunks resulting in ~43 API calls for 72 hours of data (respects OKX's 100-candle limit).

---

## 2) Cron — `src/jobs/pg_cron_metrics.sql` (append)

```sql
-- EVERY 1 MINUTE (avg_usd_conversion — minute)
SELECT
  cron.schedule_in_database(
    'ecosystem_load_metrics_minute',
    '* * * * *',                             -- every minute
    'call ecosystem.load_metrics_minute()',
    '<database_name>'
  );
```

---

## 3) Backfill (72h) — `src/jobs/init/avg_usd_conversion_minute.sql`

> Simplified approach for minute data: loads last 72 hours using 100-minute chunks to respect OKX's API limit.

```sql
---------------------------------------------
-- Initial load for avg_usd_conversion (minute)
-- Seeds recent history without hitting API limits
-- Note: Run this as a script, not inside a transaction
---------------------------------------------
do $$
declare
  -- configurable via: SET hgraph.backfill_minute_hours = '72';
  backfill_hours int := coalesce(current_setting('hgraph.backfill_minute_hours', true)::int, 72);

  -- Start from N hours ago
  start_ts timestamp9 := (date_trunc('minute', now()) - make_interval(hours => backfill_hours))::timestamp9;
  end_ts timestamp9;

  -- Use 100-minute chunks to respect OKX's 100-candle API limit
  window_minutes int := 100;
  current_minute timestamp9 := date_trunc('minute', now())::timestamp9;

begin
  -- Forward iteration: from past to present
  while start_ts < current_minute loop
    end_ts := least(start_ts + make_interval(mins => window_minutes), current_minute);

    raise notice 'Loading minute data from % to %', start_ts, end_ts;

    insert into ecosystem.metric(name, period, timestamp_range, total)
    select
      'avg_usd_conversion' as name,
      'minute' as period,
      int8range,
      total
    from ecosystem.avg_usd_conversion(
      'minute',
      start_ts::bigint,
      end_ts::bigint
    )
    where upper(int8range) is not null
    on conflict (name, period, timestamp_range)
    do update set total = excluded.total;

    -- Move window forward
    start_ts := end_ts;

    -- Throttle to avoid API rate limits
    perform pg_sleep(2);
  end loop;

  raise notice 'Backfill complete: loaded % hours of minute data', backfill_hours;
end $$;
```

---

## 4) Validation

```sql
-- Recent minute rows present and ordered
select *
from ecosystem.metric
where name = 'avg_usd_conversion' and period = 'minute'
order by timestamp_range desc
limit 90;

-- Function returns expected minute bins for last ~2 hours
select *
from ecosystem.avg_usd_conversion(
  'minute',
  (date_trunc('minute', now()) - interval '2 hours')::timestamp9::bigint,
  date_trunc('minute', now())::timestamp9::bigint
)
order by 1 desc;

-- Retention: verify oldest upper bound >= now() - 72 hours
select min(upper(timestamp_range))::timestamp
from ecosystem.metric
where name = 'avg_usd_conversion' and period = 'minute';
```

---

## Rollback

```sql
drop procedure if exists ecosystem.load_metrics_minute();
-- Unschedule via job id or name:
-- select cron.unschedule(<job_id>);
-- or delete data if needed:
delete from ecosystem.metric where name = 'avg_usd_conversion' and period = 'minute';
```

---

## Completion Notes

### API Limits Verification
- All exchange API limits verified and documented
- OKX's 100-candle limit is the constraining factor
- Backfill script adjusted to use 100-minute chunks

### Actual Usage Impact
- **Per Day**: 7,200 API calls (1,440 minutes × 5 exchanges)
- **Per Month**: ~216,000 API calls
- **Risk Assessment**: Very low - well within public endpoint limits
- **Ongoing Impact**: Negligible - only 1-2 new candles per minute after backfill

### Implementation Verified
- All files created and tested for correctness
- Follows repository patterns exactly
- PR #61 created with comprehensive documentation
