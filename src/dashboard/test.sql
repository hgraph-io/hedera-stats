        SELECT COUNT(e.id) AS total
        FROM entity e
        INNER JOIN
          (select distinct payer_account_id, result, consensus_timestamp from transaction) t
          ON t.payer_account_id = e.id
          AND e.type = 'ACCOUNT'
          and t.result = 22
        JOIN time_bounds tb ON
            t.consensus_timestamp BETWEEN tb.previous_period_start AND tb.current_period_start


        SELECT COUNT(distinct e.id) AS total
        FROM entity e
        INNER JOIN
          (select distinct payer_account_id, result, consensus_timestamp from transaction) t
          ON t.payer_account_id = e.id
          AND e.type = 'ACCOUNT'
          and t.result = 22
          and  t.consensus_timestamp
            BETWEEN (now() - '3 days'::interval)::timestamp9::bigint
            AND (now() - '2 day'::interval)::timestamp9::bigint;

        SELECT COUNT(distinct e.id) AS total
        FROM entity e
        INNER JOIN
          (select distinct payer_account_id, result, consensus_timestamp from transaction) t
          ON t.payer_account_id = e.id
          AND e.type = 'ACCOUNT'
          and t.result = 22
          and  t.consensus_timestamp
            >= (now() - '2 day'::interval)::timestamp9::bigint;

