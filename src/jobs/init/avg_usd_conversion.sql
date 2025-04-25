---------------------------------------------
-- Initial load for avg_usd_conversion metric
-- This script will load the metric from the external apis in a way that doesn't
-- pass the rate limit of the apis
----------------------
do $$
declare
 start_date timestamp9 := (select min(lower(timestamp_range))::timestamp9 - interval '8 days' from ecosystem.metric where name = 'avg_usd_conversion' and period = 'hour');
 end_date timestamp9 := (start_date + interval '4 days');

 first_transaction timestamp9 := (select min(consensus_timestamp)::timestamp9 from transaction);

begin
  while start_date > first_transaction loop
      insert into ecosystem.metric(name, period, timestamp_range, total)
        select
          'avg_usd_conversion' as name,
          'hour' as period,
          int8range,
          total
        from ecosystem.avg_usd_conversion(
          'hour',
          start_date::bigint,
          end_date::bigint
        )
        where upper(int8range) is not null
        on conflict (name, period, timestamp_range)
        do update
          set total = excluded.total ;

      start_date := start_date - interval '4 days';
      end_date := start_date + interval '4 days';

      raise notice 'start_date: %, end_date: %', start_date, end_date;
      commit;

      perform pg_sleep(5); -- to avoid too many api calls

  end loop;
end $$;
