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

## Run 4 — chain head, 28.10.2026 19:22 MSK

Command: `forge test` in the repository root with `FORK_BLOCK` unset (fork at the latest block the RPC serves).

Result: **7 passed, 0 failed** (two fuzz tests, 256 runs each).

Block context: head was **26 292 390** at the time of the run; an attempt to pin **26 291 390** failed for a
different reason worth recording — the public archive endpoint answered
`historical state ... is not available`, i.e. **the failure was the RPC's state retention, not the invariant**.
That distinction matters: a red test that is actually a dead endpoint must never be reported as a broken
protocol.

## Run 5 — pinned recent block, 29.10.2026 03:45 MSK

Command: `FORK_BLOCK=26294800 forge test` (chain head was 26 294 901 at the time, so this is ~100 blocks
behind head — close enough to be "now", far enough that the RPC still serves state).

Result: **7 passed, 0 failed** in 15 s (two fuzz tests, 256 runs each).

Why this run exists: Run 4 forked at whatever the RPC called "latest", which makes it unreproducible a day
later. Here the block number is pinned **and** recent, so the result can be re-checked by anyone while the
archive node still holds that state. Both properties matter: a pinned old block is reproducible but no longer
says anything about today's protocol; an unpinned head says something about today but cannot be re-run.

## Receipt for Run 5 — 29.10.2026

Command: `python tools/witness_receipt.py --block 26294800`
Output: `receipts/26294800.json` — **7/7 passed**, `forge_exit_code: 0`, `signed: false`.

Input digests recorded in the receipt (first 16 hex chars): test file `5d2d2daa2682e14b`,
`foundry.toml` `be4b75759aeddee3`, `CLAIMS.md` `02b9b95635ae8b36`, `NOT-CLAIMED.md` `9fecc51404dd9b28`.
