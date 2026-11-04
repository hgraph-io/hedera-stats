-- 089-load_network_deposits.sql — Hourly loader for the network deposit metrics: node_<N>_deposits plus
-- treasury_account_deposits, staking_account_deposits and node_reward_account_deposits.
--
-- Promoted from the publishers, where this procedure existed with no migration
-- (identical on the mainnet and testnet publishers unless noted below).
-- Body copied verbatim from the mainnet publisher's definition so that
-- applying it there is a no-op; behaviour changes belong in later migrations.
--
-- Publisher-side: scheduled by its own pg_cron job on the publisher (not by
-- load_metrics_*). Writes ecosystem.metric directly.

BEGIN;

CREATE OR REPLACE PROCEDURE ecosystem.load_network_deposits()
    LANGUAGE plpgsql
    AS $_$

declare

start_timestamp bigint;
end_timestamp bigint;

result_set ecosystem.metric;

begin
	set time zone 'UTC';

  --------------------------
	-- for the first run, we need to have an entry to start from
	-- select consensus_timestamp from transaction order by consensus_timestamp asc limit 1;
	-- start_timestamp := (select '2024-02-01 18:00:00'::timestamp9::bigint);
  --------------------------
  -- start at the most recent entry in the metric table
	-- start_timestamp := (select '2019-09-13 21:00:00'::timestamp9::bigint);
	start_timestamp := (select lower(timestamp_range) from ecosystem.metric where name ~ '^(atma_)?(treasury|staking|node|reward)_.*_deposits$' order by lower(timestamp_range) desc limit 1);
	end_timestamp := (start_timestamp::timestamp9 + '1 hour'::interval)::bigint;

	-- loop through each hour
	while start_timestamp < now()::timestamp9::bigint loop
		raise notice 'timestamp: %', end_timestamp::timestamp9;
		-- get crypto transfer set
		with deposits as (
			select transfer.entity_id,	transfer.payer_account_id, transfer.amount
			from crypto_transfer as transfer
			join transaction on transfer.consensus_timestamp = transaction.consensus_timestamp
			where transfer.consensus_timestamp between start_timestamp and end_timestamp
			and transfer.amount > 0
			and transfer.amount <= transaction.charged_tx_fee
			and transfer.entity_id = ANY ('{98,800,801,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34}')
		),
		node_deposits as (
			insert into ecosystem.metric (name, period, timestamp_range, total)
				select
					case
						when entity_id = 98 then 'treasury_account_deposits'
						when entity_id = 800 then 'staking_account_deposits'
						when entity_id = 801 then 'node_reward_account_deposits'
						else 'node_' || entity_id || '_deposits'
					end as name,
					'hour' as period,
					int8range(start_timestamp, end_timestamp) as timestamp_range,
					sum(amount) as total
				from deposits
				group by entity_id
			on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
			returning *
		),
		atma_node_deposits as (
			insert into ecosystem.metric (name, period, timestamp_range, total)
				select
					case
						when entity_id = 98 then 'atma_treasury_account_deposits'
						when entity_id = 800 then 'atma_staking_account_deposits'
						when entity_id = 801 then 'atma_node_reward_account_deposits'
						else 'atma_node_' || entity_id || '_deposits'
					end as name,
					'hour' as period,
					int8range(start_timestamp, end_timestamp) as timestamp_range,
					sum(amount) as total
				from deposits
				-- atma payer_account_id
				where payer_account_id = 1459478
				group by entity_id
			on conflict (name, period, timestamp_range) do update set total = EXCLUDED.total
			returning *
		)

		-- select * from node_deposits into result_set;
		-- raise notice 'node_deposits: %', result_set;

		select * from atma_node_deposits into result_set;
		raise notice 'atma_node_deposits: %', result_set;

		-- reset timestamps
		commit;
		start_timestamp := (start_timestamp::timestamp9 + '1 hour'::interval)::timestamp9::bigint;
		end_timestamp := (end_timestamp::timestamp9 + '1 hour'::interval)::timestamp9::bigint;

	end loop;

end;

$_$;

COMMIT;
