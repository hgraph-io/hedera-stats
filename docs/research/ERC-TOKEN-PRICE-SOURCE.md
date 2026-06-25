# R&D: EVM/ERC-token price source for Hedera (HG-2955)

**Status:** Research complete - **recommendation: defer ERC value-ranking**
**Scope:** Research + recommendation only. No build in this ticket.
**Blocks/relates:** HG-1631 (Top Fungible Tokens ERC), HG-2227 + HG-2301 (HTS token-price pipeline, both Done)
**Date:** 2026-06-25
**Data source:** Hedera mainnet mirror node, queried via Hgraph (https://hgraph.com)

---

## 1. Problem in one paragraph

Our value-ranked token metric (`top_fungible_tokens_hts`) needs a USD price per token. For
**HTS** tokens we get that from on-chain SaucerSwap DEX events, materialized in `dex.spot_price`
and `dex.candle`. For **ERC-20 tokens on Hedera's EVM** there is no equivalent price feed, which
is what blocks `top_fungible_tokens_erc` (HG-1631). This document checks whether a usable source
exists today and recommends a path.

## 2. Headline finding

**There is no usable price source for Hedera ERC-20 tokens today, and the gap is caused by an
absence of markets, not an absence of indexing.** The active ERC-20 tokens that do exist are
almost entirely lending-receipt, LP/vault-wrapper, and bridged-wrapper tokens that have no native
market price to begin with. A USD value-ranking of ERC-20 tokens would therefore be both
unfeasible (no price) and economically misleading (it would double-count assets already priced as
HTS). **Recommend: defer ERC value-ranking; ship HTS value-ranking + non-value / HBAR-denominated
ERC metrics now.**

## 3. Evidence (Hedera mainnet, via Hgraph)

### 3.1 ERC-20 tokens exist but are overwhelmingly dormant

| Metric | Value |
| --- | --- |
| ERC-20 contracts indexed (`erc.token`, `contract_type='ERC_20'`) | 1,886 |
| ERC-20 tokens with **any** transfer in the last 30 days | 118 (~6%) |
| ERC-20 tokens with ≥100 transfers in 30 days | 14 |
| Total ERC-20 transfers in 30 days | ~52,000 (one token, WAVE, is ~82% of that) |

(For reference: ERC-721 = 271 contracts, ERC-1400 = 24.)

### 3.2 Zero of them have a DEX market or a price

Cross-checking all 1,886 ERC-20 contract addresses against the DEX pipeline that already powers
HTS pricing:

| Check | Result |
| --- | --- |
| ERC-20 contracts appearing in **any** `dex.pool` (by EVM address) | **0 / 1,886** |
| ERC-20 contracts with a row in `dex.spot_price` | **0 / 1,886** |
| Tokens currently priced in `dex.spot_price` (all HTS) | 1,492 |
| Indexed DEX pools | 2,781 SaucerSwap v1 + 55 v2 - **HTS only** |

Note: `dex.pool` already carries `token0_evm_address` / `token1_evm_address` columns, so the
pipeline *would* capture ERC-20 pools if they existed. They don't - SaucerSwap pools are HTS, and
SaucerSwap is ~85% of all Hedera DEX volume.

### 3.3 The "active" ERC-20 tokens have no native market price *by nature*

Top ERC-20 tokens by 30-day transfer activity:

| Symbol | Name | What it actually is | Priceable on a Hedera DEX? |
| --- | --- | --- | --- |
| WAVE | Wave | Memecoin / points token | No market |
| amWHBAR, amUSDC, amHBARX, amSAUCE, aBONZO | Bonzo aTokens | Lending-protocol **receipt** tokens | No - derived from underlying HTS asset |
| variableDebtmUSDC, variableDebtmWHBAR | Bonzo debt tokens | **Debt** accounting tokens | No - not an asset |
| WETH, WBTC, WHBAR | Wrapped assets | Bridged/wrapped representations | Price = the underlying, not a Hedera market |
| ICHI_Vault_LP, bCLM-USDC-HBAR | LP / vault tokens | **LP receipt** tokens | No - value is sum of pooled assets |
| tNGN | Importa Naira | Small stablecoin | Pegged, negligible volume |

The takeaway: even if we built a price source, the ranking would be dominated by receipt/debt/LP
wrappers whose "value" is a re-representation of HTS assets we already rank. Ranking them by USD
"market cap" would double-count and mislead.

## 4. Options considered

### Option A - Index a Hedera EVM DEX the way we index SaucerSwap
**Verdict: not viable.** There is no DEX with meaningful ERC-20 volume to index. SaucerSwap (the
only indexed DEX, ~85% market share) trades HTS tokens; 0/1,886 ERC-20 contracts appear in any
pool. Building an indexer for markets that don't exist yields nothing.

### Option B - External oracle / price API (DeFi Llama, CoinGecko)
**Verdict: not viable today.**
- CoinGecko's on-chain (GeckoTerminal) coverage for Hedera is sourced from the **same SaucerSwap
  HTS pools** we already index - it adds **zero** incremental ERC-20 coverage.
- CoinGecko's listed-coins / contract-address endpoint only covers a curated set of major Hedera
  ecosystem tokens (predominantly HTS). The dormant/wrapper ERC-20 long tail is not individually
  listed. This matches the "~0% coverage" finding from when this was last checked.
- DeFi Llama is protocol-TVL oriented, not a per-token Hedera ERC-20 price feed.

### Option C - Curated top-N off-chain feed (interim)
**Verdict: poor fit, not recommended.**
- It would be spot-only, which **mismatches** the HTS pipeline's historical OHLCV model and
  HG-1631's requirement to rank across time periods.
- It needs ongoing manual maintenance.
- The list of genuinely priceable, independent ERC-20 assets on Hedera is currently tiny
  (effectively: one memecoin plus a couple of pegged stablecoins) - not worth a feed.

### Option D - Defer ERC value-ranking; ship HTS + non-value ERC metrics first
**Verdict: recommended.** See below.

## 5. Recommendation

**Defer the USD value-ranking of ERC-20 tokens (HG-1631) until a real ERC-20 market exists on
Hedera.** In the meantime, ship value where we have prices (HTS) and ship ERC where we don't need
prices:

1. **Keep HTS value-ranking** (`top_fungible_tokens_hts`) as the value-ranked fungible metric -
   it already works and covers the tokens that actually trade.
2. **Ship non-value ERC-20 metrics now** - these need no price feed and are already supported by
   `erc.token` / `erc.token_transfer` / `erc.token_account`:
   - total / new ERC-20 tokens, total ERC-20 holders, active ERC-20 tokens, transfer counts.
3. **Reframe HG-1631 as an activity-ranked metric**, mirroring the precedent already in the repo:
   `top_non_fungible_tokens_erc` ranks ERC-721 collections by **on-chain HBAR-denominated sales
   volume + transaction count** with no USD price. An ERC-20 equivalent could rank by transfer
   count, unique holders, and HBAR-denominated transfer volume where determinable - delivering a
   useful "top ERC-20 tokens" ranking without a price oracle.
4. **Set a revisit trigger.** Re-open the value-ranking question when on-chain data shows a
   genuine ERC-20 market - concretely: when the cross-check in §3.2 returns a non-trivial count of
   ERC-20 contracts in `dex.pool` / `dex.spot_price` (i.e. a Hedera DEX starts listing ERC-20
   pairs with real liquidity). At that point Options A/B become live again.

### Suggested ticket outcome
- **HG-2955:** Done (this writeup).
- **HG-1631:** either (a) close as out-of-scope-for-now with the revisit trigger above, or
  (b) re-scope to an **activity-ranked** `top_fungible_tokens_erc` (no price) and proceed. This is
  a product call - see the decision note in the PR/Linear comment.

## 6. How to reproduce the finding

All numbers come from the Hedera mainnet mirror node. Key cross-check (returns 0 / 0):

```sql
WITH erc20 AS (
  SELECT lower(token_evm_address) AS addr, token_id
  FROM erc.token WHERE contract_type = 'ERC_20'
),
pool_tokens AS (
  SELECT lower(token0_evm_address) AS addr FROM dex.pool
  UNION SELECT lower(token1_evm_address) FROM dex.pool
)
SELECT
  (SELECT COUNT(*) FROM erc20)                                                       AS erc20_total,
  (SELECT COUNT(*) FROM erc20 e WHERE e.addr     IN (SELECT addr FROM pool_tokens))  AS erc20_in_any_dex_pool,
  (SELECT COUNT(*) FROM erc20 e WHERE e.token_id IN (SELECT token_id FROM dex.spot_price)) AS erc20_with_spot_price;
```

Activity snapshot (replace the timestamp with `now_ns - 2_592_000_000_000_000` for trailing 30d):

```sql
SELECT t.token_id, t.symbol, t.name,
       (SELECT COUNT(*) FROM erc.token_transfer x
          WHERE x.token_id = t.token_id AND x.consensus_timestamp >= <NOW_NS - 30d>) AS transfers_30d,
       (SELECT COUNT(*) FROM erc.token_account a WHERE a.token_id = t.token_id AND a.balance > 0) AS holders
FROM erc.token t
WHERE t.contract_type = 'ERC_20'
ORDER BY transfers_30d DESC LIMIT 20;
```

## 7. Sources

- SaucerSwap - leading DEX on Hedera, HTS pools, ~85% market share:
  https://hedera.com/users/saucerswap , https://www.saucerswap.finance/
- HTS vs ERC-20 on Hedera (hybrid tokenization):
  https://docs.hedera.com/hedera/core-concepts/tokens/hybrid-hts-+-evm-tokenization
- CoinGecko Hedera on-chain data API (GeckoTerminal, sources Hedera DEX pools):
  https://www.coingecko.com/en/api/hedera-hashgraph
- CoinGecko coin-by-contract-address endpoint (listed coins only):
  https://docs.coingecko.com/reference/coins-contract-address
- On-chain figures: Hedera mainnet mirror node via Hgraph (https://hgraph.com), 2026-06-25.
