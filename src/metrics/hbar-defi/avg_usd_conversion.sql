-- Requires the pg_http extension for HTTP requests
create or replace function ecosystem.avg_usd_conversion(
    period text,
    start_timestamp bigint default 0,
    end_timestamp bigint default (current_timestamp::timestamp9::bigint)
)
returns setof ecosystem . metric_total
language plpgsql
volatile
as $$
declare
    orig_start_ms bigint;
    orig_end_ms bigint;
    period_ms double precision;
    period_p text := period;
    -- maximum number of candles (by OKX limit: https://www.okx.com/docs-v5/en/?shell#public-data-rest-api-get-index-candlesticks-history)
    limit_candles integer := 100;

    new_start_ms bigint;
    new_end_ms bigint;

    binance_interval text;
    okx_bar text;
    bitget_granularity text;
    mexc_interval text;

    binance_content jsonb;
    okx_content jsonb;
    bitget_content jsonb;
    mexc_content jsonb;

    rec jsonb;

    binance_url text;
    okx_url text;
    bitget_url text;
    mexc_url text;

begin
    perform http_set_curlopt('CURLOPT_TIMEOUT', '1000');
    perform http_set_curlopt('CURLOPT_CONNECTTIMEOUT', '1000');

    orig_start_ms := (start_timestamp / 1e6)::bigint;
    orig_end_ms := (end_timestamp / 1e6)::bigint;

    case period
        when 'month' then
            binance_interval := '1M';
            okx_bar := '1Mutc';
            bitget_granularity := '1Mutc';
            mexc_interval := '1M';
        when 'week' then
            binance_interval := '1w';
            okx_bar := '1Wutc';
            bitget_granularity := '1Wutc';
            mexc_interval := '1W';
        when 'day' then
            binance_interval := '1d';
            okx_bar := '1Dutc';
            bitget_granularity := '1Dutc';
            mexc_interval := '1d';
        when 'hour' then
            binance_interval := '1h';
            okx_bar := '1H';
            bitget_granularity := '1h';
            mexc_interval := '60m';
        when 'minute' then
            binance_interval := '1m';
            okx_bar := '1m';
            bitget_granularity := '1min';
            mexc_interval := '1m';
        else
            -- use month period otherwise
            binance_interval := '1M';
            okx_bar := '1Mutc';
            bitget_granularity := '1Mutc';
            mexc_interval := '1M';
            period_p := 'month';
    end case;

    period_ms := extract(epoch from ('1 ' || period_p)::interval) * 1000;

    -- calculate new start timestamp based on the period * limit_candles
    new_start_ms := least(orig_end_ms, greatest(orig_start_ms, orig_end_ms - (period_ms * limit_candles)));
    new_end_ms := orig_end_ms;

    -- binance
    binance_url :=
        'https://data-api.binance.vision/api/v3/klines'
        || '?symbol=HBARUSDT'
        || '&interval=' || binance_interval
        || '&startTime=' || new_start_ms
        || '&endTime=' || new_end_ms
        || '&limit=' || limit_candles;
    begin
        select content::jsonb into binance_content from http_get(binance_url);
        -- raise notice 'binance content: %', binance_content;
    exception when others then
        raise warning 'error fetching data from binance: %', sqlerrm;
        binance_content := '[]'::jsonb;
    end;

    -- okx
    okx_url :=
        'https://www.okx.com/api/v5/market/history-index-candles'
        || '?instId=HBAR-USDT'
        || '&bar=' || okx_bar
        || '&before=' || new_start_ms
        || '&after=' || new_end_ms
        || '&limit=' || limit_candles;
    begin
        select content::jsonb into okx_content from http_get(okx_url);
        -- raise notice 'okx content: %', okx_content;
    exception when others then
        raise warning 'error fetching data from okx: %', sqlerrm;
        okx_content := '{"data": []}'::jsonb;
    end;

    -- bitget
    bitget_url :=
        'https://api.bitget.com/api/v2/spot/market/candles'
        || '?symbol=HBARUSDT'
        || '&granularity=' || bitget_granularity
        || '&startTime=' || new_start_ms
        || '&endTime=' || new_end_ms
        || '&limit=' || limit_candles;
    begin
        select content::jsonb into bitget_content from http_get(bitget_url);
        -- raise notice 'bitget content: %', bitget_content;
    exception when others then
        raise warning 'error fetching data from bitget: %', sqlerrm;
        bitget_content := '{"data": []}'::jsonb;
    end;

    -- mexc
    mexc_url :=
        'https://api.mexc.com/api/v3/klines'
        || '?symbol=HBARUSDT'
        || '&interval=' || mexc_interval
        || '&startTime=' || new_start_ms
        || '&endTime=' || new_end_ms
        || '&limit=' || limit_candles;
    begin
        select content::jsonb into mexc_content from http_get(mexc_url);
        -- raise notice 'mexc content: %', mexc_content;
    exception when others then
        raise warning 'error fetching data from mexc: %', sqlerrm;
        mexc_content := '[]'::jsonb;
    end;

    create temporary table if not exists temp_parsed_data (
        open_time_ms bigint,
        close_price numeric
    ) on commit drop;
    truncate table temp_parsed_data;

    -- parse binance data
    for rec in
        select * from jsonb_array_elements(binance_content) as candle
    loop
        insert into temp_parsed_data (open_time_ms, close_price)
        values (
            (rec->>0)::bigint,
            (rec->>4)::numeric
        );
    end loop;

    -- parse okx data
    for rec in
        select * from jsonb_array_elements(okx_content->'data') as candle
    loop
        insert into temp_parsed_data (open_time_ms, close_price)
        values (
            (rec->>0)::bigint,
            (rec->>4)::numeric
        );
    end loop;

    -- parse bitget data
    for rec in
        select * from jsonb_array_elements(bitget_content->'data') as candle
    loop
        insert into temp_parsed_data (open_time_ms, close_price)
        values (
            (rec->>0)::bigint,
            (rec->>4)::numeric
        );
    end loop;

    -- parse mexc data
    for rec in
        select * from jsonb_array_elements(mexc_content) as candle
    loop
        insert into temp_parsed_data (open_time_ms, close_price)
        values (
            (rec->>0)::bigint,
            (rec->>4)::numeric
        );
    end loop;

    return query
    with grouped as (
        select
            date_trunc (
                period,
                to_timestamp (open_time_ms / 1000.0)
            ) as truncated_ts,
            avg(close_price * 1e5)::bigint as avg_close
        from
            temp_parsed_data
        group by 1
        order by 1
    ),
    final_output as (
        select
            int8range(
                truncated_ts::timestamp9::bigint,
                (lead(truncated_ts) over (order by truncated_ts rows between current row and 1 following))::timestamp9::bigint
            ) as timestamp_range,
            avg_close as total
        from
            grouped
    )
    select * from final_output;
end;
$$;
