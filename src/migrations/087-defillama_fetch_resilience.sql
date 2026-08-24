-- 087-defillama_fetch_resilience.sql — the DeFiLlama endpoints serve a warm CDN
-- cache in ~200ms but take 30s+ on a cache miss, so a 10s timeout fails a run
-- roughly daily. Retries each fetch, checks the HTTP status, and resets the
-- session curlopts on the failure path too.

BEGIN;

create or replace procedure ecosystem.load_network_tvl()
language plpgsql
as $$
declare
    url constant text := 'https://api.llama.fi/v2/historicalChainTvl/Hedera';
    max_attempts constant integer := 3;
    attempt integer := 0;
    response_status integer;
    response_content text;
    payload jsonb;
    last_error text;
begin
    perform http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS', '5000');
    perform http_set_curlopt('CURLOPT_TIMEOUT_MS', '45000');

    while attempt < max_attempts loop
        attempt := attempt + 1;
        begin
            select status, content into response_status, response_content from http_get(url);

            if response_status <> 200 then
                raise exception 'HTTP % from %', response_status, url;
            end if;

            payload := response_content::jsonb;

            if jsonb_typeof(payload) <> 'array' then
                raise exception 'expected a JSON array from %, got %', url, jsonb_typeof(payload);
            end if;

            exit;
        exception when others then
            payload := null;
            last_error := sqlerrm;
            raise warning 'load_network_tvl attempt %/% failed: %', attempt, max_attempts, last_error;
            if attempt < max_attempts then
                perform pg_sleep(2 * attempt);
            end if;
        end;
    end loop;

    perform http_reset_curlopt();

    if payload is null then
        raise exception 'load_network_tvl: % attempts to fetch % failed, last error: %',
            max_attempts, url, last_error;
    end if;

    insert into ecosystem.metric (name, period, timestamp_range, total)
    select
        'network_tvl',
        'day',
        int8range(
            (to_timestamp((series_point ->> 'date')::numeric))::timestamp9::bigint,
            (to_timestamp((series_point ->> 'date')::numeric) + '1 day'::interval)::timestamp9::bigint
        ),
        (series_point ->> 'tvl')::numeric
    from jsonb_array_elements(payload) as series_point
    on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;
end;
$$;

create or replace procedure ecosystem.load_stablecoin_marketcap()
language plpgsql
as $$
declare
    url constant text := 'https://stablecoins.llama.fi/stablecoincharts/Hedera';
    max_attempts constant integer := 3;
    attempt integer := 0;
    response_status integer;
    response_content text;
    payload jsonb;
    last_error text;
begin
    perform http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS', '5000');
    perform http_set_curlopt('CURLOPT_TIMEOUT_MS', '45000');

    while attempt < max_attempts loop
        attempt := attempt + 1;
        begin
            select status, content into response_status, response_content from http_get(url);

            if response_status <> 200 then
                raise exception 'HTTP % from %', response_status, url;
            end if;

            payload := response_content::jsonb;

            if jsonb_typeof(payload) <> 'array' then
                raise exception 'expected a JSON array from %, got %', url, jsonb_typeof(payload);
            end if;

            exit;
        exception when others then
            payload := null;
            last_error := sqlerrm;
            raise warning 'load_stablecoin_marketcap attempt %/% failed: %', attempt, max_attempts, last_error;
            if attempt < max_attempts then
                perform pg_sleep(2 * attempt);
            end if;
        end;
    end loop;

    perform http_reset_curlopt();

    if payload is null then
        raise exception 'load_stablecoin_marketcap: % attempts to fetch % failed, last error: %',
            max_attempts, url, last_error;
    end if;

    insert into ecosystem.metric (name, period, timestamp_range, total)
    select
        'stablecoin_marketcap',
        'day',
        int8range(
            (to_timestamp((series_point ->> 'date')::numeric))::timestamp9::bigint,
            (to_timestamp((series_point ->> 'date')::numeric) + '1 day'::interval)::timestamp9::bigint
        ),
        (series_point -> 'totalCirculating' ->> 'peggedUSD')::numeric
    from jsonb_array_elements(payload) as series_point
    on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;
end;
$$;

COMMIT;
