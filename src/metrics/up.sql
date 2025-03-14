-------------------------------
-- Setup
-------------------------------

-- metrics table
create table if not exists ecosystem.metric (
    -- naming convention: <entity>_<action> (e.g. account_associated_nft)
    name text,
    period text,
    timestamp_range int8range,
    total bigint,
    unique (name, period, timestamp_range)
);
-- if migrating from a previous version
-- alter table ecosystem.metric add unique (name, period, timestamp_range);
-- alter table ecosystem.metric drop constraint metric_name_timestamp_range_key;

-- metric_description table
create table if not exists ecosystem.metric_description (
    name text primary key not null,
    description text,
    methodology text
);


insert into ecosystem.metric_description (name, description, methodology)
values
    ('accounts_associating_nfts', 'Number of accounts that associated NFTs during the period', ''),
    ('accounts_receiving_nfts', 'Number of accounts that received NFTs during the period', ''),
    ('accounts_sending_nfts', 'Number of accounts that sent NFTs during the period', ''),
    ('accounts_minting_nfts', 'Number of accounts that minted NFTs during the period', ''),
    ('accounts_creating_nft_collections', 'Number of accounts that created NFT collections during the period', ''),
    ('active_nft_accounts', 'Number of active NFT accounts during the period', ''),
    ('active_nft_builder_accounts', 'Number of active NFT builder accounts during the period', ''),
    ('nft_collections_created', 'Number of NFT collections created during the period', ''),
    ('nfts_minted', 'Number of NFTs minted during the period', ''),
    ('nfts_transferred', 'Number of NFTs transferred during the period', ''),
    ('nft_sales_volume', 'Volume of NFT sales during the period', ''),
    ('active_developer_accounts', 'Developer across the different Hedera services, measured by the number of unique accounts that submit these creative transaction types during the period.', ''),
    ('active_retail_accounts', 'Accounts that do transactions but are not smart contracts or developers during the period', ''),
    ('active_smart_contracts', 'The number of unique smart contracts that have had activity during the period', ''),
    ('active_accounts', 'The number equal developers + retails + smart contracts during the period', ''),
    ('network_fee', 'The total network fee for the period during the period', ''),
    ('account_growth', 'The number of created accounts that do transactions but are not smart contracts or developers during the period', ''),
    ('network_tps', 'The number of transactions per second during the period', ''),
    ('total_nfts', 'Total number of NFTs in the ecosystem', ''),
    ('nft_holders', 'Total number of NFT holders in the ecosystem', ''),
    ('nft_market_cap', 'Total market capitalization of NFTs in the ecosystem', ''),
    ('nft_holders_per_period', 'Number of NFT holders during the period', ''),
    ('network_tvl', 'Total value locked (USD) in the ecosystem during the period', ''),
    ('stablecoin_marketcap', 'Total market capitalization (USD) of stablecoins in the ecosystem during the period', ''),
    ('avg_usd_conversion', 'Average conversion of HBAR to US dollars multiplied by 10,000 during the period', 'The average of candlestick closing prices for a given period for the HBAR/USDT pair on the five major exchanges by trading volume (Binance, Bybit, OKX, Bitget and MEXC) was calculated. The price is multiplied by 10,000 for integer representation for each time period.')
on conflict (name) do update
set
    description = excluded.description,
    methodology = excluded.methodology;

-- return type for metric calculation functions
do $$ begin
	create type ecosystem.metric_total as (
			int8range int8range,
			total bigint
	);
	raise notice 'CREATE TYPE';
exception
    when duplicate_object
			then
				raise notice 'type "ecosystem.metric_total" already exists, skipping';
end $$;

-------------------------------
-- Load metrics
-------------------------------
create or replace procedure ecosystem.load_metrics()
language plpgsql
as $$

declare
    periods text[] := array['day', 'week', 'month', 'quarter', 'year', 'century'];
    current_period text;

    metrics text[] := array [
        'accounts_associating_nfts',
        'accounts_receiving_nfts',
        'accounts_sending_nfts',
        'accounts_minting_nfts',
        'accounts_creating_nft_collections',
        'active_nft_accounts',
        'active_nft_builder_accounts',
        'nft_collections_created',
        'nfts_minted',
        'nfts_transferred',
        'nft_sales_volume',
        -- network_tvl and stablecoin_marketcap raw data are updated in DefiLlama every day at midnight
        'network_tvl',
        'stablecoin_marketcap',
        'avg_usd_conversion'
    ];
    metric text;

    total_time timestamp;
    metric_loop_time timestamp;
    period_loop_time timestamp;

begin
    set time zone 'UTC';
    total_time := clock_timestamp();

    -- Insert current totals for 3 metrics
    insert into ecosystem.metric (name, period, timestamp_range, total)
        select 'total_nfts' as name, 'century' as period, int8range as timestamp_range, total
        from ecosystem.current_total_nfts() on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

    insert into ecosystem.metric (name, period, timestamp_range, total)
        select 'nft_holders' as name, 'century' as period, int8range as timestamp_range, total
        from ecosystem.current_nft_holders() on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

    insert into ecosystem.metric (name, period, timestamp_range, total)
        select 'nft_market_cap' as name, 'century' as period, int8range as timestamp_range, total
        from ecosystem.current_nft_market_cap() on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total;

    -- Metrics for different time intervals
    foreach metric in array metrics loop
        metric_loop_time := clock_timestamp();

        foreach current_period in array periods loop
            period_loop_time := clock_timestamp();

            raise notice 'metric: %, period: %', metric, current_period;
            declare
                starting_timestamp bigint := 0;
            begin
                execute format ('
                    select coalesce(max(upper(timestamp_range)), 0::bigint)
                    from ecosystem.metric
                    where period = %L
                    and name = %L
                    ', current_period, metric)
                    into starting_timestamp;

                raise notice 'metric: %, starting_timestamp: %', metric, starting_timestamp;

                execute format('
                    insert into ecosystem.metric (name, period, timestamp_range, total)
                    select %L as name, %L as period, int8range as timestamp_range, total
                    from ecosystem.%s(%L::text, %L::bigint) where upper(int8range) is not null
                    on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total'
                    , metric, current_period, metric, current_period, starting_timestamp);
                commit;

                raise notice E'\n metric_loop_time: %,\n period_loop_time: %,\n total_time: % \n'
                , clock_timestamp() - metric_loop_time, clock_timestamp() - period_loop_time, clock_timestamp() - total_time;
            end;
        end loop;
    end loop;
end;
$$;


-- hourly job
create or replace procedure ecosystem.load_hourly_metrics()
language plpgsql
as $$

declare

    metrics text[] := array [
        'accounts_associating_nfts',
        'accounts_receiving_nfts',
        'accounts_sending_nfts',
        'accounts_minting_nfts',
        'accounts_creating_nft_collections',
        'active_nft_accounts',
        'active_nft_builder_accounts',
        'nft_collections_created',
        'nfts_minted',
        'nfts_transferred',
        'nft_sales_volume',
        'active_developer_accounts',
        'active_retail_accounts',
        'active_smart_contracts',
        'active_accounts',
        'network_fee',
        'account_growth',
        'network_tps',
        'avg_usd_conversion'
    ];
    metric_name text;

    total_time timestamp;
    metric_loop_time timestamp;

    end_timestamp_bigint bigint;
    last_upper_bound bigint;
begin
    set time zone 'utc';
    total_time := clock_timestamp();

    -- Truncate current time to hour so we don't include a partial hour
    end_timestamp_bigint := date_trunc('hour', now())::timestamp9::bigint;

    raise notice 'loading hourly metrics up to % (utc)', (end_timestamp_bigint)::timestamp9;

    foreach metric_name in array metrics loop
        metric_loop_time := clock_timestamp();

        select coalesce(max(upper(timestamp_range)), 0)
          into last_upper_bound
          from ecosystem.metric
         where period = 'hour'
           and name = metric_name;

        raise notice 'metric: %, last_upper_bound: % => % (utc)',
                     metric_name,
                     last_upper_bound,
                     (last_upper_bound)::timestamp9;

        if last_upper_bound >= end_timestamp_bigint then
            raise notice 'no new full hours to insert for metric %', metric_name;
        else
            execute format($sql$
                insert into ecosystem.metric (name, period, timestamp_range, total)
                select %L as name,
                       'hour' as period,
                       int8range,
                       total
                  from ecosystem.%I('hour', %s, %s)
                  where upper(int8range) is not null
                on conflict (name, period, timestamp_range)
                do update
                  set total = excluded.total
            $sql$, metric_name, metric_name, last_upper_bound, end_timestamp_bigint);

            commit;
        end if;

        raise notice e'\n metric_loop_time: %,\n total_time: % \n',
                     clock_timestamp() - metric_loop_time,
                     clock_timestamp() - total_time;
    end loop;

end;
$$;

-------------------------------
-- Helpers
-------------------------------
create or replace function ecosystem.metric_start_date(_row ecosystem . metric)
returns timestamp
language sql stable
as $$
	select lower(_row.timestamp_range)::timestamp9::timestamp at time zone 'UTC';
$$;

create or replace function ecosystem.metric_end_date(_row ecosystem . metric)
returns timestamp
language sql stable
as $$
	select upper(_row.timestamp_range)::timestamp9::timestamp at time zone 'UTC';
$$;
