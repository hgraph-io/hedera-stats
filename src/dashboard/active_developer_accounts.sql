-----------------------
-- Total active developer accounts
-- select ecosystem.dashboard_active_developer_accounts('90 days');
-- select ecosystem.dashboard_active_developer_accounts('7 days', true);
-- select ecosystem.dashboard_active_developer_accounts('30 days', true);
-- select ecosystem.dashboard_active_developer_accounts('90 days', true);
-----------------------
create or replace function ecosystem.dashboard_active_developer_accounts(
    _interval interval, change boolean = false
)
returns decimal as $$

declare total decimal;
previous_period_start bigint = (NOW() - _interval * 2)::timestamp9::bigint;
current_period_start bigint = (NOW() - _interval )::timestamp9::bigint;

begin
  -- get percent change
  if change then
    with previous_period AS (
      select count(*) as total from (
        SELECT distinct payer_account_id AS total
        FROM transaction t
        where t.consensus_timestamp BETWEEN previous_period_start AND current_period_start
          AND t.type IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
          and t.result = 22 -- Success result
      )
    ),
    current_period AS (
      select count(*) as total from (
        SELECT distinct payer_account_id AS total
        FROM transaction t
        where t.consensus_timestamp >= current_period_start
          AND t.type IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
          and t.result = 22 -- Success result
      )
    )
    SELECT
        ((current_period.total::DECIMAL / NULLIF(previous_period.total, 0)) - 1) * 100 into total
    FROM current_period, previous_period;
  else
    select count(*) from (
      select distinct payer_account_id into total
      from transaction as t
      where t.consensus_timestamp >= current_period_start
        and t.type IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
        and t.result = 22 -- Success result
    );
  end if;
  return total;
end;
$$ language plpgsql;
