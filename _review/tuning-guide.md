# Tuning guide: top_fungible_tokens_hts PoC

Operator manual for [poc.sql](poc.sql) review and tuning sessions. This doc covers how to turn the knobs and read the output. Full column definitions and methodology rationale: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens.

## Control panel

All knobs live in the `1. CONTROLS` section of poc.sql (the `params` CTE). The first three mirror the locked function signature; the rest are PoC-only and stay as literals at conversion (README, conversion note 1).

| Knob | Default | What it tunes | Effect class |
| --- | --- | --- | --- |
| `window_hours` | 24 | Lookback span, snapped to complete UTC hours (clamped `GREATEST(., 1)` in the function) | membership |
| `result_limit` | 50 | Rows returned (NULL or 0 yields 0 rows, not all rows) | display |
| `min_liquidity_hbar` | 1000 | Data-quality floor on the selected price row (clamped `GREATEST(., 0)` in the function) | membership |
| `min_volume_usd` | 100 | Eligibility volume floor | membership |
| `max_mcap_volume_ratio` | 50000 | Ceiling on mcap/volume for the low-volume entry path | membership |
| `weight_market_cap` | 0.4 | Composite emphasis on size | ordering |
| `weight_volume` | 0.4 | Composite emphasis on DEX trading | ordering |
| `weight_transactions` | 0.2 | Composite emphasis on network usage | ordering |
| `anchor_hours_ago` | 0 | 0 = live board; N = the board as of N complete hours ago | mode |

Effect classes:

- **display**: nothing recomputes; only the rows shown change.
- **ordering**: the survivor set and every raw and normalized value stay identical; only the contribution columns, composite_score, and rank move. Weights are therefore the safe instant knob for live A/B within the same hour.
- **membership**: the survivor set changes, and because min-max normalization runs across survivors, EVERY normalized value and score shifts, including for tokens the change did not touch. Compare membership lists and raw values across such runs, not scores.
- **mode**: switches the valuation source. At anchor 0 prices come from the live spot table; at N > 0 everything (prices, liquidity, supply, activity) is reconstructed as of the anchor hour. See Anchored boards below.

### Window presets

`window_hours` presets: hour 1, day 24, week 168, month 720. All four validated live 2026-06-06 direct on the mirror node (probes in validation-results.md): day ~0.27s / 121 survivors, week ~1.6s / 216, month ~6.6s / 287; hour candles reach back to 2022-11-30, so month is fully data-backed. Runtimes are direct-only; FDW in the standalone container is unmeasured at any window. Three notes for non-default windows: BOTH eligibility thresholds are calibrated at 24h, and they move in opposite directions: `min_volume_usd` 100 admits proportionally more tokens at longer windows, while the `max_mcap_volume_ratio` clause WEAKENS at longer windows (window volume grows roughly linearly, so the ratio shrinks and the anti-garbage gate admits more low-volume/high-cap tokens) and over-restricts at 1h. At the 1h preset the survivor set is smaller (26 at a sample hour, request 2a3caa03, normalization non-degenerate there with all three ln-ranges healthy); a very quiet hour could shrink it enough to make min-max scores fragile, though the NULLIF/COALESCE guards keep it from erroring and the display norms render 0, not NULL. And `pct_change_24h` reads as pct change over the configured window (the name is exact only at the default). To place a window in the PAST, combine a preset with `anchor_hours_ago` (next section).

## Weight scheme

House style: decimals summing to 1.0 (for example 0.4 / 0.4 / 0.2). The `weights` CTE divides each weight by their sum, so ratio inputs such as 4 / 4 / 2 behave identically. Note the limits: normalization fixes the SUM, not the intent; it cannot detect a wrong-proportion typo (0.4 / 0.4 / 0.4 silently becomes a valid-looking equal-weight board). All-zero weights raise a division-by-zero error on purpose: a broken configuration should fail loudly, not rank silently.

### Anchored boards

`anchor_hours_ago` N > 0 reconstructs the board as of N complete hours ago, HONESTLY: prices and liquidity come from the last hour candle per (token, source) at or before the anchor, supply from the token-history range covering that hour, and activity from the window ending there. Validated end-to-end 2026-06-06 (battery 6): week-back boards in ~0.5s, month-back in ~0.3s. Notes:

- Reconstruction, not a recording: an anchored board is rebuilt from hourly candle closes and as-of supply; it is NOT what the live board displayed at that hour and can legitimately differ, because (i) the live board prices from intra-hour ticks, not the hour close, (ii) deepest-pool selection runs on candle liquidity and may pick a different source than the spot snapshot did, and (iii) the 30-day staleness gate (next bullet) drops tokens the live board would have shown with older spot prices. An anchored board for the current hour is not defined (anchor 0 IS the present).
- Staleness rule: a token must have traded within 30 days before the anchor to be priced (the lookback literal in the anchored branch; independent of the month window preset despite both being 720 hours). Stricter than the live table, which has no recency bound, so anchored composition is not a time-shifted live board.
- Floor calibration: the 1,000 HBAR floor's near-zero board impact was validated on spot liquidity (phase 1 probes); its impact on candle liquidity in anchored mode is unvalidated.
- Derived-source prices do not exist historically (no candles); such tokens are floor-excluded on the live board anyway.
- Tokens created after the anchor are correctly absent (no supply row covers the hour).
- Fully deterministic: two runs with the same anchor reproduce EXACTLY, every column including prices and scores (battery 6 full-column digest pair). Anchored boards are safe to screenshot for decks; live boards drift with spot prices. Reproducible is NOT comparable: composite_score and the contribution columns are min-max rescaled within each board's own survivor set, so never compare scores ACROSS different anchors or windows; compare ranks and raw components (mcap, volume, transactions) instead.
- Anchors before 2022-11-30 (the first hour candle) return an empty board; documented, not guarded.
- Composes with presets: anchor 168 + window 24 = the day board one week ago; anchor 0 + window 168 = the trailing week ending now.

## Structural levers (methodology, not knobs)

These are positions of the methodology of record; changing one is an algorithm change to discuss before editing, not a tuning action: ln(1+x) concave scaling, min-max normalization across survivors, deepest-liquidity price selection, all-sources volume vs single-source pct_change, distinct-consensus-timestamp transaction counting, and the deterministic tie-break (composite DESC, volume DESC, token_id ASC). Definitions and rationale: phase 1 doc.

## Reading the output

Columns arrive in four groups (order is the spec; the future function adopts it):

1. **Ranks** (`rank`, `market_cap_rank`, `volume_rank`): `rank` is the composite product; the other two are reference frames computed over the full eligible set. Divergence is the story: rank 4 with mcap rank 14 is an activity-lifted token; rank 8 with mcap rank 2 is size without activity.
2. **Identity** (`token_symbol`, `token_name`, `token_id`): token_id is the only identity; symbols collide freely.
3. **Scoring** (`composite_score` + the three contribution columns): contributions sum to the score; the largest one is why the token sits where it does.
4. **Market data** (`price_usd` through `liquidity_usd`): the raw signals.

After these come the normalized intermediates, then `price_as_of` (the selected price row's consensus time, surfacing staleness) and the six normalization-bound parity columns (`bound_min/max_ln_mcap|vol|tx`, constant within a run, the Phase-2 feed), then the DEBUG block (`window_end_utc` showing which hour the board represents, `eligibility_clause`, `price_source`, ln values) which exists for diagnosis and drops at function conversion.

## Comparing runs

The window snaps to the most recent complete UTC hour, so any two runs inside the same hour see the same candles and transfers (the volume and transaction components are reproducible); the live spot price AND the live `total_supply` drift, so market cap, composite, and rank can move between two runs in the same hour. The board is a live board, not bit-identical across refreshes; `price_as_of` shows each row's price age. Weight changes are directly comparable run-to-run. Membership changes are not score-comparable (see effect classes). Anchored runs are exactly reproducible, so anchored A/B comparisons (same anchor, different knobs) are free of drift entirely; across DIFFERENT anchors compare ranks and raw components only, never composite scores (set-dependent). For strict comparisons use the digest technique recorded in validation-results.md. Survivor counts drift across hours (recent windows: 110 to 287 depending on window length and anchor); differences between documents are window drift, not contradictions.

## Run notes

- poc.sql is ONE statement; run the whole file. DBeaver: Cmd+A then Cmd+Enter, or untick Preferences > Editors > SQL Editor > SQL Processing > "Blank line is statement delimiter".
- Comments in poc.sql must stay free of DDL/cursor keywords; some read-only gateways filter query text including comments.
- Runtime direct against the mirror node scales with the window: roughly 250ms at the 24h default, ~1.6s at week, ~6.6s at month (window-preset probes). FDW runtime in the standalone container is unmeasured (build-round item).
- Prices read from `dex.latest` through the `spot_price` indirection until the prod move to `dex.spot_price` lands (hg-core #1201).

## Section map

| poc.sql section | CTEs | What happens |
| --- | --- | --- |
| 1. CONTROLS | params, weights | All knobs; weight normalization |
| 2. TIME BOUNDS | bounds | Trailing window snapped to the complete UTC hour |
| 3. PRICE SELECTION | spot_price, selected_price | One price per token, deepest liquidity wins; live spot or as-of the anchor |
| 4. ELIGIBILITY | candidates, vol, px_change, survivors | Priced HTS fungibles, liquidity floor, volume/ratio filter |
| 5. SCORING | tx, scored, normalized, composite | Usage counts, ln(1+x), min-max, weighted sum |
| 6. OUTPUT | final SELECT | Ordering, rounding, parity + DEBUG columns |

## Sources

- [poc.sql](poc.sql) (the workbench) and the shipped function at `src/metrics/hbar-defi/top_fungible_tokens_hts.sql`
- Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens
