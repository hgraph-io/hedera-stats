-- helper function to get the summary of a metric over the last 7, 30, and 90 days

create or replace function ecosystem.get_metric_summary(
    metric_name_param text,
    end_timestamp bigint default date_trunc('hour', now())::timestamp9::bigint,
    based_period text default 'hour',
    agg_method text default 'sum'
)
returns table (
    metric_name text,
    current_value bigint,
    change_7d double precision,
    change_30d double precision,
    change_90d double precision
)
language plpgsql
as $$
declare
    start_7d bigint := end_timestamp - interval '7 days';
    start_30d bigint := end_timestamp - interval '30 days';
    start_90d bigint := end_timestamp - interval '90 days';
    total_current_7d bigint;
    total_previous_7d bigint;
    total_current_30d bigint;
    total_previous_30d bigint;
    total_current_90d bigint;
    total_previous_90d bigint;
begin
    -- Current 7-day period
    select ecosystem.get_aggregated_value(
        agg_method,
        metric_name_param,
        based_period,
        start_7d,
        end_timestamp
    )
    into total_current_7d;

    -- Previous 7-day period
    select ecosystem.get_aggregated_value(
        agg_method,
        metric_name_param,
        based_period,
        (start_7d - interval '7 days')::bigint,
        start_7d
    )
    into total_previous_7d;

    -- Current 30-day period
    select ecosystem.get_aggregated_value(
        agg_method,
        metric_name_param,
        based_period,
        start_30d,
        end_timestamp
    )
    into total_current_30d;

    -- Previous 30-day period
    select ecosystem.get_aggregated_value(
        agg_method,
        metric_name_param,
        based_period,
        (start_30d - interval '30 days')::bigint,
        start_30d
    )
    into total_previous_30d;

    -- Current 90-day period
    select ecosystem.get_aggregated_value(
        agg_method,
        metric_name_param,
        based_period,
        start_90d,
        end_timestamp
    )
    into total_current_90d;

    -- Previous 90-day period
    select ecosystem.get_aggregated_value(
        agg_method,
        metric_name_param,
        based_period,
        (start_90d - interval '90 days')::bigint,
        start_90d
    )
    into total_previous_90d;

    return query
    select
        metric_name_param as metric_name,
        total_current_90d as current_value,
        ecosystem.calculate_change(total_current_7d,  total_previous_7d)  as change_7d,
        ecosystem.calculate_change(total_current_30d, total_previous_30d) as change_30d,
        ecosystem.calculate_change(total_current_90d, total_previous_90d) as change_90d
    ;
end;
$$;
