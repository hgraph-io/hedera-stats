-----------------------
-- Total active developer accounts
-----------------------
create or replace function ecosystem.dashboard_active_developer_accounts(
    _interval interval
)
returns bigint as $$
  select count(*) from (
    select distinct payer_account_id
    from transaction t
    where t.consensus_timestamp >=  (now() - _interval::interval)::timestamp9::bigint
      and t.type IN (8, 9, 24, 25, 29, 36, 37, 58) -- Smart Contract Create / Update Transaction, Token Create / Update / Mint (FT & NFT) Transaction / TokenAirdrop, Create / Update Topic Transaction
      and t.result = 22 -- Success result
  );
$$ language sql;
