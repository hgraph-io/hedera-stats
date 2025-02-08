CREATE TEMP TABLE metric_temp (
    name TEXT,
    period TEXT,
    timestamp_range INT8RANGE,
    total BIGINT
);

COPY metric_temp (name, period, timestamp_range, total) FROM STDIN with (format csv, header true);

merge into ecosystem.metric as target
  using metric_temp as source
  on target.name = source.name
  and target.period = source.period
  and target.timestamp_range = source.timestamp_range
  when matched then
    update set total = source.total
  when not matched then
    insert (name, period, timestamp_range, total)
    values (source.name, source.period, source.timestamp_range, source.total);


-- SELECT * FROM metric_temp LIMIT 5;  -- Optional: Check if data is loaded
