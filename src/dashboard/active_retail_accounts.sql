-----------------------
-- Total active retail accounts
-- select ecosystem.dashboard_active_retail_accounts('90 days');
-- select ecosystem.dashboard_active_retail_accounts('7 days', true);
-- select ecosystem.dashboard_active_retail_accounts('30 days', true);
-- select ecosystem.dashboard_active_retail_accounts('90 days', true);
-----------------------
create or replace function ecosystem.dashboard_active_retail_accounts(_interval interval, change boolean = false)
returns decimal as $$
declare total decimal;
begin
  -- get percent change
  if change then
    WITH time_bounds AS (
        SELECT
            (NOW() - _interval * 2)::timestamp9::bigint AS previous_period_start,
            (NOW() - _interval)::timestamp9::bigint AS current_period_start
    ),
    previous_period AS (
        SELECT COUNT(distinct t.payer_account_id) AS total
        FROM transaction t
        JOIN entity e ON t.payer_account_id = e.id AND e.type = 'ACCOUNT'
        JOIN time_bounds tb ON
            t.consensus_timestamp BETWEEN tb.previous_period_start AND tb.current_period_start
        WHERE t.result = 22 -- Success result
        AND t.type NOT IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
    ),
    current_period AS (
        SELECT COUNT(distinct t.payer_account_id) AS total
        FROM transaction t
        JOIN entity e ON t.payer_account_id = e.id AND e.type = 'ACCOUNT'
        JOIN time_bounds tb ON
            t.consensus_timestamp >= tb.current_period_start
        WHERE t.result = 22 -- Success result
        AND t.type NOT IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
    )
    SELECT
        ((current_period.total::DECIMAL / NULLIF(previous_period.total, 0)) - 1) * 100 into total
    FROM current_period, previous_period;
  --return total
  else
    select count(distinct e.id) into total
    from transaction as t
    inner join entity as e on t.payer_account_id = e.id
    where t.result = 22 and e.type = 'ACCOUNT'
      and t.consensus_timestamp >= (now() - _interval::interval)::timestamp9::bigint
      and t.type NOT IN (8, 9, 24, 25, 29, 36, 37, 58); -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
  end if;
  return total;
end;
$$ language plpgsql;
