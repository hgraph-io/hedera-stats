-- 082-nft_holders_per_period.sql — per-period distinct NFT holder counts
-- Moved from the legacy ecosystem schema; tracked in Hasura.

BEGIN;

---------------------------------
-- nft_holders_per_period
---------------------------------

create or replace function ecosystem.nft_holders_per_period (
    token_id        bigint,
    period          text,
    start_timestamp bigint default 0,
    end_timestamp   bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem.metric
language plpgsql stable
as
$$
declare
    p_token_id bigint := token_id;
begin
    return query
    with nft_holders_history as (
        /*
          1) collect intervals from history and current state.
        */
        select
            account_id,
            lower(timestamp_range) as start_ts,
            upper(timestamp_range) as end_ts
        from nft_history
        where nft_history.token_id = p_token_id

        union all

        select
            account_id,
            lower(timestamp_range) as start_ts,
            upper(timestamp_range) as end_ts
        from nft
        where nft.token_id = p_token_id
    ),
    intervals as (
        /*
          2) filter intervals that intersect [start_timestamp, end_timestamp].
             if end_ts is null, it means "infinite" ownership.
        */
        select
            account_id,
            start_ts,
            end_ts
        from nft_holders_history
        where start_ts <= end_timestamp
          and (
              end_ts >= start_timestamp
              or end_ts is null
          )
    ),
    extremes as (
        /*
          3) find min and max timestamps
        */
        select
           min(start_ts) as min_ts,
           case
              when bool_or(end_ts is null) then end_timestamp
              else max(end_ts)
           end as max_ts
        from intervals
    ),
    raw_buckets as (
        /*
          4) generate time points from min_ts to max_ts
        */
        select generate_series(
            to_timestamp((ext.min_ts / 1e9)::double precision),
            to_timestamp((ext.max_ts / 1e9)::double precision),
            cast('1 ' || period as interval)
        ) as bucket_start
        from extremes ext
    ),
    time_buckets as (
        /*
          5) form buckets [bucket_start, bucket_end) using lead(...).
        */
        select
            rb.bucket_start,
            coalesce(
                lead(rb.bucket_start) over (order by rb.bucket_start),
                to_timestamp((ext.max_ts / 1e9)::double precision)
            ) as bucket_end
        from raw_buckets rb
        cross join extremes ext
    ),
    holders_count as (
        /*
          6) for each bucket [bucket_start, bucket_end), find all intervals
             [start_ts, end_ts) that intersect with it.
             intersection condition (semi-open intervals):
               i.start_ts < bucket_end
               and (i.end_ts is null or i.end_ts > bucket_start)
        */
        select
            tb.bucket_start,
            tb.bucket_end,
            count(distinct i.account_id) as total
        from time_buckets tb
        left join intervals i
               on i.start_ts <  tb.bucket_end::timestamp9::bigint
                  and (
                      i.end_ts is null
                      or i.end_ts > tb.bucket_start::timestamp9::bigint
                  )
        group by tb.bucket_start, tb.bucket_end
        order by tb.bucket_start
    )
    select
       'nft_holders_per_period' as name,
       period,
       int8range(
         tb.bucket_start::timestamp9::bigint,
         tb.bucket_end::timestamp9::bigint
       ) as timestamp_range,
       total
    from holders_count tb
    order by tb.bucket_start;
end;
$$;

COMMIT;
