CREATE
OR
replace FUNCTION ecosystem.active_ed25519_accounts( period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT CURRENT_TIMESTAMP::timestamp9::bigint )
returns setof ecosystem.metric_total AS $$ WITH ed25519_transactions AS
(
       SELECT t.consensus_timestamp,
              t.payer_account_id
       FROM   TRANSACTION t
       JOIN   entity e
       ON     t.payer_account_id = e.id
       AND    t.consensus_timestamp BETWEEN start_timestamp AND    end_timestamp
       AND    e.type = 'ACCOUNT'
       AND    e.KEY IS NOT NULL
       AND    e.created_timestamp IS NOT NULL
       AND    (
                     e.public_key LIKE '302a300506032b6570%') ), ed25519_accounts_per_period AS
(
         SELECT   date_trunc(period, consensus_timestamp::timestamp9::timestamp) AS period_start_timestamp,
                  count(DISTINCT payer_account_id)                               AS total
         FROM     ed25519_transactions
         GROUP BY 1
         ORDER BY 1 DESC )SELECT   int8range( period_start_timestamp::timestamp9::bigint, (lead(period_start_timestamp) OVER (ORDER BY period_start_timestamp rows BETWEEN CURRENT row AND      1 following))::timestamp9::bigint ),
         total
FROM     ed25519_accounts_per_period $$ language sql stable;