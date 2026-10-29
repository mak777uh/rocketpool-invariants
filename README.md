# rETH accounting invariants — a re-runnable witness

A small Foundry harness that pins Rocket Pool's rETH to **mainnet state** and asserts six accounting
properties. It is written so that a reviewer can re-run it and get the same numbers, instead of reading a
report and trusting it.

Part of the [Rocket Pool GMC Round 42](https://dao.rocketpool.net/t/4070) proposal *"Invariant witness for
rETH mint/redeem paths"* — this repository is the first, deliberately narrow slice of that work.

## The claim, in one sentence

On three pinned blocks, the rETH mint/burn **quotes** never let a round trip or a dust amount come back with
more ETH than it went in with, the exchange rate does not fall over a simulated 30-day interval, and when
deposits are gated the contract does not take the caller's ETH.

## What is verified

| test | property |
|---|---|
| `test_RoundTripNeverProfits` | ETH → rETH → ETH does not create ETH (1 ETH case) |
| `testFuzz_RoundTripNeverProfits` | same, 200 random amounts in [0.0001, 10 000] ETH |
| `testFuzz_SmallAmountRounding` | dust (1 wei … 0.001 ETH): quote never returns more value than the input |
| `test_ExchangeRateNonDecreasing` | rate does not fall over a simulated 30 days |
| `test_ExchangeRateAtLeastParity` | rate ≥ 1 ETH per rETH |
| `test_LiveDepositIsGatedOrConserved` | when `deposit()` reverts, the caller's ETH is not taken |
| `test_BurnPathPaysAtMostRate` | burn pays no more than quoted, and records "unavailable" honestly when the path is closed |

Run it:

```bash
forge install foundry-rs/forge-std
export MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io   # any archive RPC
forge test --match-contract REthAccountingTest -vv --fuzz-runs 200

# historical blocks (deposit/burn had different states there)
FORK_BLOCK=21500000 forge test --match-contract REthAccountingTest -vv
FORK_BLOCK=20000000 forge test --match-contract REthAccountingTest -vv
```

Expected: **7 passed** on each block.

## Evidence discipline

This repository follows the claim-registry method: every statement about the protocol is typed by its
evidence, and the wording is constrained by the type.

| file | role |
|---|---|
| [CLAIMS.md](CLAIMS.md) | every claim, its evidence type (`test` / `measurement` / `reading`), and the strongest permitted wording |
| [METRICS.md](METRICS.md) | every number with the exact command and log line that produced it |
| [NOT-CLAIMED.md](NOT-CLAIMED.md) | what this witness explicitly refuses to assert — the most important file here |
| [tools/check_claims.py](tools/check_claims.py) | fails if a claim points at a test that does not exist, or if the suite does not pass |

```bash
python tools/check_claims.py --run     # claim registry + test suite, one command
```

## Two things the first version got wrong (kept in the record)

1. **`getTotalCollateral()` is the liquid buffer**, not the staked ETH backing rETH. An early invariant
   compared it with `totalSupply × rate` and "failed" by a factor of 140. The invariant was ill-posed, not
   the protocol. See [NOT-CLAIMED.md](NOT-CLAIMED.md).
2. **Both user-facing paths are gated on the pinned blocks**: `deposit()` reverts with no reason string, and
   `burn` reverts for lack of deposit-pool liquidity. The harness therefore asserts the *safety of the gated
   state* rather than pretending the open state was exercised.

## What this is not

Not an audit, not a proof, not a guarantee. Seven tests on three blocks are a witness; the absence of a
counterexample in 200 fuzz runs is evidence, not proof. The beacon-chain side of rETH accounting is not read
here at all.

## License

MIT (see [LICENSE](LICENSE)). The write-up is CC BY 4.0.

## Reproducible receipt (slice 1)

`tools/witness_receipt.py` runs the invariant suite against a pinned block and writes a JSON receipt:
the block number, the digests of the test file and the claim documents, and the per-test result.

```bash
python tools/witness_receipt.py --block 26294800
# receipts/26294800.json  ->  7/7 passed, exit 0
```

The receipt is **reproducible, not attested**: it carries `"signed": false` and says so in
`signature_note`. Two runs on the same block with the same input digests must agree on the `tests` array;
if they do not, the code or the environment changed. Signing is deliberately out of scope for slice 1 — a
receipt that claims more than it can prove is exactly the failure mode this repository exists to avoid.
