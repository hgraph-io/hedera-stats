CREATE
OR
replace FUNCTION ecosystem.new_smart_contracts( period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT CURRENT_TIMESTAMP::timestamp9::bigint )
returns setof ecosystem.metric_total language sql stable AS $$ WITH all_entries AS
(
       SELECT e.created_timestamp
       FROM   entity e
       JOIN   TRANSACTION t
       ON     e.created_timestamp = t.consensus_timestamp
       WHERE  e.type = 'CONTRACT'
       AND    t.type = 8    -- CONTRACTCREATEINSTANCE
       AND    t.result = 22 -- SUCCESS
       AND    e.created_timestamp BETWEEN start_timestamp AND    end_timestamp ), contracts_per_period AS
(
         SELECT   date_trunc(period, created_timestamp::timestamp9::timestamp) AS period_start_timestamp,
                  count(*)                                                     AS total
         FROM     all_entries
         GROUP BY 1
         ORDER BY 1 ASC )SELECT   int8range( period_start_timestamp::timestamp9::bigint, (lead(period_start_timestamp) OVER (ORDER BY period_start_timestamp rows BETWEEN CURRENT row AND      1 following))::timestamp9::bigint ),
         total
FROM     contracts_per_period $$;