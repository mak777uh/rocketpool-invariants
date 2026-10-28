# Metrics — every number with the command that produced it

Fork blocks: **26 290 581** (current state, deposits gated), **21 500 000**, **20 000 000** (historical).
RPC: any archive endpoint; the runs below used `https://eth-mainnet.public.blastapi.io`.

Command template (all rows):

```bash
export MAINNET_RPC_URL=<archive-rpc>
export FORK_BLOCK=<block or unset for latest>
forge test --match-contract REthAccountingTest -vv --fuzz-runs 200
```

| # | metric | value | block | command / log line |
|---|---|---|---|---|
| M1 | exchange rate | `1.174609541108734450` | 26 290 581 | `forge test --match-test test_ExchangeRateNonDecreasing -vv` → `rate 0:` |
| M2 | exchange rate | `1.124601584061279393` | 21 500 000 | same, with `FORK_BLOCK=21500000` |
| M3 | exchange rate | `1.107608133167161834` | 20 000 000 | same, with `FORK_BLOCK=20000000` |
| M4 | 1 ETH round trip: rETH minted | `851346736938712879` | 26 290 581 | `test_RoundTripNeverProfits` → `rETH:` |
| M5 | 1 ETH round trip: ETH back | `999999999999999999` | 26 290 581 | same → `back:` |
| M6 | fuzz cases for round trip | `200` per block | all three | `--fuzz-runs 200`, all pass |
| M7 | fuzz cases for dust rounding | `200` per block | all three | `testFuzz_SmallAmountRounding`, all pass |
| M8 | deposit state | `GATED` (revert, no reason string) | all three | `test_LiveDepositIsGatedOrConserved` → `deposit GATED on this fork block: ETH conserved` |
| M9 | burn state | `unavailable` (deposit-pool liquidity) | all three | `test_BurnPathPaysAtMostRate` → `burn unavailable on this fork block (deposit pool liquidity)` |
| M10 | test suite size | `7 tests, 7 passed` | all three | `Suite result: ok. 7 passed; 0 failed` |
| M11 | gas of the cheapest invariant test | `≈ 23 600` | 26 290 581 | `test_ExchangeRateAtLeastParity` gas |

## How these numbers were produced

`forge test` with `-vv` prints the values above through `emit log_named_uint`. No number in this file was
copied from a report, a dashboard or a model output; each is a log line of a run in this repository.

## What is deliberately absent

- No total-value-locked, no supply, no collateral coverage figure: `getTotalCollateral()` is the liquid
  buffer, so any "coverage" ratio computed from it would be misleading (see `NOT-CLAIMED.md`).
- No beacon-chain numbers (validator balances, penalties): the harness cannot read them.
- No timing or throughput claims: the harness is a correctness witness, not a benchmark.
