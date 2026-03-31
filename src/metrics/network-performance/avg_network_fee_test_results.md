# avg_network_fee Test Results

Tested 2026-03-17 against Hedera mirror node via [Hgraph](https://hgraph.com).

## Daily Period (last 7 days)

| Day        | Avg Fee (tinybar) | Tx Count | Min Fee | Max Fee       |
| ---------- | ----------------: | -------: | ------: | ------------: |
| 2026-03-17 |         2,632,576 |  187,642 |  15,889 | 1,713,552,984 |
| 2026-03-16 |         2,653,001 |  277,466 |  16,036 | 1,796,355,997 |
| 2026-03-15 |         2,286,219 |  267,415 |  16,618 | 1,923,964,145 |
| 2026-03-14 |         2,426,377 |   79,862 |  17,318 | 1,875,484,879 |

## Hourly Period (last 12 hours)

| Hour (UTC) | Avg Fee (tinybar) |
| ---------- | ----------------: |
| 16:00      |         2,292,324 |
| 15:00      |         2,874,864 |
| 14:00      |         2,089,743 |
| 13:00      |         2,071,002 |
| 12:00      |         2,676,962 |
| 11:00      |         2,151,767 |
| 10:00      |         1,906,546 |
| 09:00      |         2,437,033 |
| 08:00      |         2,030,933 |
| 07:00      |         2,871,970 |
| 06:00      |         2,185,808 |
| 05:00      |         2,305,963 |

## Notes

- Transactions with `charged_tx_fee = 0` are excluded from the average.
- `avg(charged_tx_fee)::bigint` truncates to integer, consistent with tinybar convention.
- Max fees (~17-19 HBAR) are orders of magnitude above the average (~0.026 HBAR), indicating sensitivity to outlier contract calls.
