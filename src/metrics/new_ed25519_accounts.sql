CREATE
OR
replace FUNCTION ecosystem.new_ed25519_accounts( period text, start_timestamp bigint DEFAULT 0, end_timestamp bigint DEFAULT CURRENT_TIMESTAMP::timestamp9::bigint )
returns setof ecosystem.metric_total language sql stable AS $$ WITH all_entries AS
(
       SELECT e.id,
              e.created_timestamp
       FROM   entity e
       WHERE  e.type = 'ACCOUNT'
       AND    e.KEY IS NOT NULL
       AND    substring(e.KEY FROM 1 FOR 2) = e'\\x1220'
       AND    e.created_timestamp BETWEEN start_timestamp AND    end_timestamp ), accounts_per_period AS
(
         SELECT   date_trunc(period, to_timestamp(created_timestamp / 1e9)) AS period_start_timestamp,
                  count(*)                                                  AS total
         FROM     all_entries
         GROUP BY 1
         ORDER BY 1 ASC )SELECT   int8range( period_start_timestamp::timestamp9::bigint, ( lead(period_start_timestamp) OVER (ORDER BY period_start_timestamp rows BETWEEN CURRENT row AND      1 following) )::timestamp9::bigint ),
         total
FROM     accounts_per_period $$;