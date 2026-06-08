# Review aids (branch `hg-2956` only — not part of the build)

These files support the Hashgraph/team review of `top_fungible_tokens_hts` (HG-2956). They sit at the
repo root, outside the container-mounted `src/`, so the init script never loads them and they cannot
affect the build. They are removed in the pre-merge cleanup.

- `poc.sql` — the tunable workbench: a superset of the shipped function with the full knob set
  (weights, eligibility thresholds, and an anchored historical mode). At its default knobs (the live
  board) its output equals `ecosystem.top_fungible_tokens_hts`. Run it to tweak the algorithm and
  compare boards during review.
- `tuning-guide.md` — operator manual: what each knob does, window presets, reading the output, and
  comparing runs.

Shipped function: `src/metrics/hbar-defi/top_fungible_tokens_hts.sql`.
Methodology: https://docs.hgraph.com/hedera-stats-wip/top-50-fungible-tokens
