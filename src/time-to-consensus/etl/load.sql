create temp table metric_temp (
    name text,
    period text,
    timestamp_range int8range,
    total bigint,
    unique (name, period, timestamp_range)
);

\copy metric_temp (name, period, timestamp_range, total)
  from '/root/hedera-stats/src/time-to-consensus/etl/../.raw/output.csv'
  with (FORMAT csv, HEADER true);


-- merge into ecosystem.metric as target
--   using metric_temp as source
--   on target.name = source.name
--   and target.period = source.period
--   and target.timestamp_range = source.timestamp_range
--   when matched then
--     update set total = source.total
--   when not matched then
--     insert (name, period, timestamp_range, total)
--     values (source.name, source.period, source.timestamp_range, source.total);
