# Coverage matrix — what is proved, what is tested, what is not covered

This file is the deliverable promised in the grant application: for every statement in the repository, its
**evidence type**, where it lives, and its current status. The rule is simple and enforced by review: a
statement may never be listed with a stronger evidence type than the artifact that supports it.

Evidence types (the vocabulary used across our repositories):

| type | meaning |
|---|---|
`proof` | a checker (Lean kernel) accepted it; no `sorry`, no extra axioms |
`test` | a deterministic test suite passes on a pinned block; it can fail, and it has |
`statistics` | a measurement with a stated sample and method |
`observation` | read from a primary source once, with the source recorded |
`judgment` | reasoning without mechanical support — always labelled as such |

## Slice M1 — mint, burn, exchange rate (`test/REthAccounting.t.sol`)

| # | statement | type | status | evidence |
|---|---|---|---|---|
M1.1 | `test_RoundTripNeverProfits` — ETH → rETH → ETH never returns more than deposited | `test` | passes | 5 forks (20 000 000 / 21 500 000 / 26 290 581 / head / 26 294 800) |
M1.2 | `testFuzz_RoundTripNeverProfits` — same, 256 fuzzed amounts | `test` | passes | same forks |
M1.3 | `testFuzz_SmallAmountRounding` — rounding never favours the user at small sizes | `test` | passes | same forks |
M1.4 | `test_BurnPathPaysAtMostRate` — the burn path never pays above the quoted rate | `test` | passes | same forks |
M1.5 | `test_ExchangeRateAtLeastParity` — the rate never falls below 1 ETH per rETH | `test` | passes | same forks; **holds on the blocks tested only** |
M1.6 | `test_ExchangeRateNonDecreasing` — the rate does not decrease without burn events | `test` | passes | same forks |
M1.7 | `test_LiveDepositIsGatedOrConserved` — the live deposit path is either closed or value-conserving | `test` | passes | same forks |

## Slice M2 — deposit pool and rate source (`test/DepositPoolInvariants.t.sol`)

| # | statement | type | status | evidence |
|---|---|---|---|---|
M2.1 | `test_DepositPoolBalanceWithinMaximum` — balance ≤ declared maximum (16.34 ETH vs 6 000 000 ETH at 26 294 800) | `test` | passes | blocks 26 294 800 and 26 290 581 |
M2.2 | `test_NetworkTotalCoversDepositPool` — network total ETH ≥ pool balance (362 610 ETH vs 16.34 ETH) | `test` | passes | same two blocks |
M2.3 | `test_ExcessBalanceSubsetOfBalance` — excess ≤ balance — excess is a subset, not an independent counter | `test` | passes | same two blocks |
M2.4 | `test_ExchangeRateMatchesNetworkTotal` — rate within 0.1% of `getTotalETHBalance() / totalSupply()` | `test` | passes after one failure | same two blocks; the 0.1% band is the daily oracle cadence, measured at 0.0455% |


## Slice M3 — vault solvency (`test/VaultSolvency.t.sol`)

| # | statement | type | status | evidence |
|---|---|---|---|---|
M3.1 | `test_VaultCoversDepositPoolLiability` — real ETH in `RocketVault` ≥ the pool's liability | `test` | passes | blocks 26 294 800 (367.74 vs 16.34 ETH) and 24 000 000 (317.62 vs 0.60 ETH) |
M3.2 | `test_PoolBalanceIsVaultEntry` — `depositPool.getBalance()` equals the vault entry exactly | `test` | passes | both blocks; values match bit-for-bit |
M3.3 | `test_PoolLiabilityBelowVaultTotal` — liability never exceeds the vault's entire ETH | `test` | passes | both blocks |

Addresses are resolved from `RocketStorage` **at the fork block**, because the deposit pool moved
(`0xdd3f…5af8` → `0xce15…4fdc`); querying the current address at an old block returns empty, which is easily
mistaken for a zero balance. That mistake is recorded in `HYPOTHESES.md` as lesson for H8.

## Infrastructure (not protocol statements, but auditable)

| item | type | status | evidence |
|---|---|---|---|
reproducible receipt | `test` | verified both directions | `receipts/26294800.json`, 11/11; tampering with a digest makes the verifier exit 1 |
receipt verifier | `test` | states its own limit | `--rerun` reproduces the set and statuses; block provenance is **not** provable without a signature (`signed: false`) |

## Not covered — and this list is the important one

| area | status | why |
|---|---|---|
minipool distribution and balances | **not covered** | requires enumerating minipools; milestone M3 |
node-operator collateral boundary | **not covered** | M3; the accounting where user funds meet operator bond |
withdrawal / redemption queues | **not covered** | M3 |
bridge paths (L2 rETH) | **not covered** | out of scope for this grant |
theorem-level proof of any of the above | **not covered** | Lean models are a separate deliverable; no kernel-checked statement exists for these paths yet |
behaviour on blocks other than those listed | **unknown** | a green suite on five blocks says nothing about block six |

## How to re-check this table

```bash
FORK_BLOCK=26294800 forge test -vv                     # 11 tests
python tools/witness_receipt.py --block 26294800       # writes receipts/26294800.json
python tools/verify_receipt.py receipts/26294800.json --rerun
```

If any line in this table and the artifacts disagree, the artifacts win. This file is a map, not the terrain.

