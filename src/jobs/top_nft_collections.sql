-----------------------
-- top_nft_collections
-- Refreshes ranking cache for top NFT collections
-----------------------
create or replace procedure ecosystem.load_top_nft_collections()
as $$

  -- Refresh top NFT collections ranking (72-hour window, top 50, no concentration filter)
  -- This query can be used to populate a materialized view or cache table
  -- Example: CREATE TABLE IF NOT EXISTS ecosystem.top_nft_collections_cache AS
  SELECT * FROM ecosystem.top_non_fungible_tokens_erc(72, 50, 1.0);

$$ language sql;
