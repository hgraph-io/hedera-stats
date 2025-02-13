-----------------------
-- Total active developer accounts
-----------------------
create or replace function ecosystem.dashboard_active_developer_accounts(
    _interval interval
)
returns table (
    total bigint,
    previous_total bigint
) as $$

declare
  total bigint;
  previous_total bigint;

  previous_period_start bigint = (now() - _interval * 2)::timestamp9::bigint;
  current_period_start bigint = (now() - _interval )::timestamp9::bigint;
begin

  select count(*) into previous_total from (
    select distinct payer_account_id
    from transaction t
    where t.consensus_timestamp between previous_period_start and current_period_start
      and t.type IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
      and t.result = 22 -- Success result
  );

  select count(*) into total from (
    select distinct payer_account_id
    from transaction t
    where t.consensus_timestamp >= current_period_start
      and t.type IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
      and t.result = 22 -- Success result
  );
  return query select total, previous_total;
end
$$ language plpgsql;
