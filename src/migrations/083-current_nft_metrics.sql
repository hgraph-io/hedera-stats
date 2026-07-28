-- 083-current_nft_metrics.sql — the three point-in-time NFT metric functions
-- that 014-load_metrics_beta.sql calls: current_total_nfts, current_nft_holders,
-- current_nft_market_cap. Promoted from src/metrics/legacy.
--
-- No migration defined them, so 014 applied cleanly (a plpgsql body is only
-- syntax-checked at CREATE time, not name-resolved) but load_metrics_beta would
-- fail at call time on any database that did not already have them from the
-- pre-migration hand-apply. This closes that gap; 083 landing after 014 is fine
-- for the same reason — plpgsql resolves the callees when the procedure runs.
--
-- Publisher-side: they read mirror-node tables (nft, nft_history,
-- crypto_transfer) and are driven by the publisher's cron entry for
-- load_metrics_beta. Grants come from 082's ALTER DEFAULT PRIVILEGES.

BEGIN;

create or replace function ecosystem.current_total_nfts()
returns setof ecosystem.metric_total
language sql stable
as $$

select
int8range(0, CURRENT_TIMESTAMP::timestamp9::bigint) as timestamp_range,
(
  select count(distinct(token_id, serial_number))
  from nft
  where deleted is false
) as total

$$;

create or replace function ecosystem.current_nft_holders()
returns setof ecosystem.metric_total
language sql stable
as $$

select
int8range(0, CURRENT_TIMESTAMP::timestamp9::bigint),
(
  select count(distinct account_id)
  from nft
  where deleted is false
) as total

$$;

create or replace function ecosystem.current_nft_market_cap()
returns setof ecosystem.metric_total
language sql stable
as $$

with latest_sale_per_nft as (
  select distinct on (token_id, serial_number) timestamp_range
  from nft_history
  -- remove minting transactions
  where spender is not null
  -- most recent sale
  order by token_id, serial_number, upper(timestamp_range) desc

),
nft_hbar_transfers as (
  select amount, consensus_timestamp
  from latest_sale_per_nft as ls
  left join crypto_transfer as ct
  on ct.consensus_timestamp = upper(ls.timestamp_range)
  where ct.amount > 0

)

select
int8range(0, CURRENT_TIMESTAMP::timestamp9::bigint) as timestamp_range,
sum(amount) as total
from nft_hbar_transfers

$$;

COMMIT;
