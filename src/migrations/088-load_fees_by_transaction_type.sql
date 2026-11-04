-- 088-load_fees_by_transaction_type.sql — Hourly loader for the per-transaction-type fee metrics (transaction_type_<N>_fees)
-- and their ATMA counterparts, written straight into ecosystem.metric.
--
-- Promoted from the publishers, where this procedure existed with no migration
-- (identical on the mainnet and testnet publishers unless noted below).
-- Body copied verbatim from the mainnet publisher's definition so that
-- applying it there is a no-op; behaviour changes belong in later migrations.
--
-- Publisher-side: scheduled by its own pg_cron job on the publisher (not by
-- load_metrics_*). Writes ecosystem.metric directly.

BEGIN;

CREATE OR REPLACE PROCEDURE ecosystem.load_fees_by_transaction_type()
    LANGUAGE plpgsql
    AS $$

declare

start_timestamp bigint;
end_timestamp bigint;

result_set ecosystem.metric;

begin
	set time zone 'UTC';

  --------------------------
	-- for the first run, we need to have an entry to start from
	-- select consensus_timestamp from transaction order by consensus_timestamp asc limit 1;
	-- mainnet: start_timestamp := (select '2024-02-01 18:00:00'::timestamp9::bigint);
	-- testnet: start_timestamp := (select '2019-09-13 21:00:00'::timestamp9::bigint);
  --------------------------

  -- start at the most recent entry in the metric table
	-- start_timestamp := (select '2019-09-13 21:00:00'::timestamp9::bigint);
	start_timestamp := (select lower(timestamp_range) from ecosystem.metric where name like 'transaction_type_%_fees' order by lower(timestamp_range) desc limit 1);
	end_timestamp := (start_timestamp::timestamp9 + '1 hour'::interval)::bigint;


	-- loop through each hour
	while start_timestamp < now()::timestamp9::bigint loop
		raise notice 'timestamp: %', end_timestamp::timestamp9;

		-- get transactions in the hour
		with transactions as (
			select type, charged_tx_fee, payer_account_id
			from transaction
			where consensus_timestamp between start_timestamp and end_timestamp
		),
		transaction_fees_by_type as (
			insert into ecosystem.metric (name, period, timestamp_range, total)
				select
					-- 'transaction_type_22_fee'
					'transaction_type_' || type || '_fees' as name,
					'hour' as period,
					int8range(start_timestamp, end_timestamp) as timestamp_range,
					sum(charged_tx_fee) as total
				from transactions
				group by type
			on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
			returning *
		),
		atma_transaction_fees_by_type as (
			insert into ecosystem.metric (name, period, timestamp_range, total)
				select
					-- 'transaction_type_22_fee'
					'atma_transaction_type_' || type || '_fees' as name,
					'hour' as period,
					int8range(start_timestamp, end_timestamp) as timestamp_range,
					sum(charged_tx_fee) as total
				from transactions
				where payer_account_id = 1459478
				group by type
			on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
			returning *
		)

		-- select * from transaction_fees_by_type into result_set;
		-- raise notice 'transaction_fees_by_type: %', result_set;

		select * from atma_transaction_fees_by_type into result_set;
		raise notice 'atma_transaction_fees_by_type: %', result_set;

		-- reset timestamps
		commit;
		start_timestamp := (start_timestamp::timestamp9 + '1 hour'::interval)::timestamp9::bigint;
		end_timestamp := (end_timestamp::timestamp9 + '1 hour'::interval)::timestamp9::bigint;

	end loop;
end;
$$;

COMMIT;
