-- 084-defillama_http_timeout_fix.sql — http_set_curlopt() is session-scoped in
-- pgsql-http; avg_usd_conversion set CURLOPT_TIMEOUT/CURLOPT_CONNECTTIMEOUT
-- (ambiguous seconds-vs-ms) and never reset them, leaking into every other
-- http_get() on the same backend — including network_tvl and
-- stablecoin_marketcap, which set no timeout of their own. Switches
-- avg_usd_conversion to the unambiguous _MS names and resets after its own
-- calls, and gives both DeFiLlama fetchers an explicit timeout of their own
-- instead of relying on ambient session state.

BEGIN;

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
    perform http_set_curlopt('CURLOPT_TIMEOUT_MS', '1000');
    perform http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS', '1000');

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
    exception when others then
        raise warning 'error fetching data from mexc: %', sqlerrm;
        mexc_content := '[]'::jsonb;
    end;

    perform http_reset_curlopt();

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

create or replace procedure ecosystem.load_network_tvl()
as $$

  select http_set_curlopt('CURLOPT_TIMEOUT_MS', '10000');

  with defillama as (
    select
        (jsonb_array_elements(content) ->> 'date')::numeric as date_sec,
        (jsonb_array_elements(content) ->> 'tvl')::numeric as tvl
    from (
      select content::jsonb as content
      from http_get('https://api.llama.fi/v2/historicalChainTvl/Hedera')
    )
  ),
  transformed as (
    select
      int8range(
        (to_timestamp(date_sec))::timestamp9::bigint,
        (to_timestamp(date_sec) + '1 day'::interval)::timestamp9::bigint
      ) as timestamp_range,
    tvl
    from defillama
  )

  insert into ecosystem.metric (name, period, timestamp_range, total)
  select 'network_tvl', 'day', timestamp_range, tvl
  from transformed
  on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

  select http_reset_curlopt();

$$ language sql;

create or replace procedure ecosystem.load_stablecoin_marketcap()
as $$

  select http_set_curlopt('CURLOPT_TIMEOUT_MS', '10000');

  with defillama as (
    select
        (jsonb_array_elements(content)->>'date')::numeric as date_sec,
        (jsonb_array_elements(content)->'totalCirculating'->> 'peggedUSD')::numeric as marketcap
    from (
      select content::jsonb as content
      from http_get('https://stablecoins.llama.fi/stablecoincharts/Hedera')
    )
  ),
  transformed as (
    select
      int8range(
        (to_timestamp(date_sec))::timestamp9::bigint,
        (to_timestamp(date_sec) + '1 day'::interval)::timestamp9::bigint
      ) as timestamp_range,
    marketcap
    from defillama
  )

  insert into ecosystem.metric (name, period, timestamp_range, total)
  select 'stablecoin_marketcap', 'day', timestamp_range, marketcap
  from transformed
  on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

  select http_reset_curlopt();

$$ language sql;

COMMIT;
