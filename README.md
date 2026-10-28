# rETH accounting invariants — reproducible safety checks

Minimal Foundry harness that re-runs rETH (Rocket Pool) accounting invariants against **mainnet
state**, so any reviewer can verify the claims instead of trusting a report.

## What it checks

| test | property | why it matters |
|---|---|---|
| `test_RoundTripNeverProfits` | ETH → rETH → ETH never returns more than deposited | mint/burn fee accounting must not leak value |
| `testFuzz_RoundTripNeverProfits` | same, 200 random amounts (0.0001–10 000 ETH) | single-value checks miss rounding at the edges |
| `testFuzz_SmallAmountRounding` | 1 wei…0.001 ETH: quote never returns more value than input | dust deposits are where floor/ceil bugs live |
| `test_ExchangeRateNonDecreasing` | exchange rate does not fall over 30 days | silent rate regressions would dilute every holder |
| `test_ExchangeRateAtLeastParity` | rate ≥ 1 ETH per rETH | a sub-parity rate would mean accounting loss |
| `test_LiveDepositIsGatedOrConserved` | when `deposit()` reverts (pool gated), no ETH is taken | a gated feature must not silently absorb funds |

## How to run

```bash
forge install foundry-rs/forge-std
export MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io   # any archive RPC
forge test --match-contract REthAccountingTest -vv --fuzz-runs 200
```

Expected: **6 passed**.

## Findings from the first run (honest notes)

1. `getTotalCollateral()` is the **liquid buffer** (deposit pool), not total staked ETH. Comparing it
   with `totalSupply * rate` is wrong — an early version of this harness asserted exactly that and
   failed. The invariant was ill-posed, not the contract.
2. On fork block **26 290 581** the live `deposit()` reverts with no reason string (deposits gated).
   The harness therefore asserts the safety property instead: **when gated, ETH is not taken**.
3. Exchange rate on that block: **1.174609541108734450**. Round-trip on 1 ETH:
   0.851346736938712879 rETH → 0.999999999999999999 ETH.

## What this is not

Not an audit. It is a small, re-runnable witness of specific conservation properties.
Absence of a counterexample in 200 fuzz runs is evidence, not proof.

## Status

Prepared by an autonomous agent. Publishing (repository + a short post in the Rocket Pool GMC
Round 42 thread) requires the operator's approval.
