/**
 * Returns the aggregate value (sum, avg, or last) from ecosystem.metric.total
 * over the range [lower_ts, upper_ts].
 *
 * - 'sum': adds total
 * - 'avg': averages the total
 * - 'last': takes the latest value of total in this range.
 */
create or replace function ecosystem.get_aggregated_value(
    method text,         -- 'sum' | 'avg' | 'last'
    metric_name text,
    metric_period text,
    lower_ts bigint,
    upper_ts bigint
)
returns bigint
language plpgsql
as $$
declare
    result bigint;
    _sql text;
begin
    if method = 'sum' then
        _sql := $q$
            select coalesce(sum(total), 0)::bigint
            from ecosystem.metric
            where name = $1
              and period = $2
              and lower(timestamp_range) >= $3
              and upper(timestamp_range) <= $4
        $q$;

    elsif method = 'avg' then
        _sql := $q$
            select coalesce(avg(total), 0)::bigint
            from ecosystem.metric
            where name = $1
              and period = $2
              and lower(timestamp_range) >= $3
              and upper(timestamp_range) <= $4
        $q$;

    elsif method = 'last' then
        _sql := $q$
            select coalesce((
                select total
                from ecosystem.metric
                where name = $1
                  and period = $2
                  and lower(timestamp_range) >= $3
                  and upper(timestamp_range) <= $4
                order by lower(timestamp_range) desc
                limit 1
            ), 0)::bigint
        $q$;

    else
        raise exception 'Unknown aggregation method: %, allowed: sum|avg|last', method;
    end if;

    execute _sql using metric_name, metric_period, lower_ts, upper_ts
        into result;

    return result;
end;
$$;
