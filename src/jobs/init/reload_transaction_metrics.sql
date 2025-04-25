create or replace procedure ecosystem.reload_transaction_metrics()
language plpgsql
as $$

declare

start_timestamp bigint;
end_timestamp bigint;

result_set ecosystem.metric;

begin
  set time zone 'UTC';


  -- start at the start of the day for the first transaction
  start_timestamp := (select consensus_timestamp::timestamp9::date::timestamp9::bigint as start_timestamp from transaction order by consensus_timestamp asc limit 1);
  end_timestamp := (start_timestamp::timestamp9 + '1 hour'::interval)::bigint;


  -- loop through each hour
  while start_timestamp < now()::timestamp9::bigint loop
    raise notice 'timestamp: %', end_timestamp::timestamp9;

    -- get transaction set
    with transactions as (
      select payer_account_id, charged_tx_fee
      from transaction
      where consensus_timestamp between start_timestamp and end_timestamp
    ),
    all_transactions as (
      insert into ecosystem.metric (name, period, timestamp_range, total)
      select
      'transactions' as name,
      'hour' as period,
      int8range(start_timestamp, end_timestamp) as timestamp_range,
      count(*) as total
      from transactions
      on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
      returning *
    ),
    atma_transactions as (
      insert into ecosystem.metric (name, period, timestamp_range, total)
      select
      'atma_transactions' as name,
      'hour' as period,
      int8range(start_timestamp, end_timestamp) as timestamp_range,
      count(*) as total
      from transactions
      where payer_account_id = 1459478
      on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
      returning *
    ),
    other_transactions as (
      insert into ecosystem.metric (name, period, timestamp_range, total)
      select
      -- name change for consistency: `update ecosystem.metric set name = 'other_transactions' where name = 'non_atma_transactions'`
      'other_transactions' as name,
      'hour' as period,
      int8range(start_timestamp, end_timestamp) as timestamp_range,
      count(*) as total
      from transactions
      where payer_account_id <> 1459478
      on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
      returning *
    ),
    all_fees as (
      insert into ecosystem.metric (name, period, timestamp_range, total)
      select
      -- name change for consistency: `update ecosystem.metric set name = 'transaction_fees' where name = 'all_charged_tx_fees'`
      'transaction_fees' as name,
      'hour' as period,
      int8range(start_timestamp, end_timestamp) as timestamp_range,
      sum(charged_tx_fee) as total
      from transactions
      on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
      returning *
    ),
    atma_fees as (
      insert into ecosystem.metric (name, period, timestamp_range, total)
      select
      -- name change for consistency: `update ecosystem.metric set name = 'atma_transaction_fees' where name = 'atma_charged_tx_fees'`
      'atma_transaction_fees' as name,
      'hour' as period,
      int8range(start_timestamp, end_timestamp) as timestamp_range,
      sum(charged_tx_fee) as total
      from transactions
      where payer_account_id = 1459478
      on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
      returning *
    ),
    other_fees as (
      insert into ecosystem.metric (name, period, timestamp_range, total)
      select
      -- name change for consistency: `update ecosystem.metric set name = 'other_transaction_fees' where name = 'non_atma_charged_tx_fees'`
      'other_transaction_fees' as name,
      'hour' as period,
      int8range(start_timestamp, end_timestamp) as timestamp_range,
      sum(charged_tx_fee) as total
      from transactions
      where payer_account_id <> 1459478
      on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
      returning *
    )

    select * from all_transactions into result_set;

    raise notice 'all_transactions: %', result_set;


    -- reset timestamps
    commit;
    start_timestamp := (start_timestamp::timestamp9 + '1 hour'::interval)::timestamp9::bigint;
    end_timestamp := (end_timestamp::timestamp9 + '1 hour'::interval)::timestamp9::bigint;

end loop;

end;

$$;
