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