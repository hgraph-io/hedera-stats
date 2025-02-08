create temp table ecosystem.metric_temp (
    name text,
    period text,
    timestamp_range int8range,
    total bigint,
    unique (name, period, timestamp_range)
);

copy ecosystem.metric_temp (name, period, timestamp_range, total)
  from :'csv';

merge into ecosystem.metric as target
  using ecosystem.metric_temp as source
  on target.name = source.name, target.period = source.period, target.timestamp_range = source.timestamp_range
  when matched then
    update set total = source.total
  when not matched then
    insert (name, period, timestamp_range, total)
    values (source.name, source.period, source.timestamp_range, source.total);
