# Claim registry — rETH accounting witness

Every statement this repository makes about rETH belongs to exactly one evidence type. The wording in a
document is only permitted if the evidence column supports it — the same discipline as
[flowguard-spec](https://github.com/mak777uh/flowguard-spec/blob/main/docs/CLAIMS.md).

Evidence types used here:

| type | meaning |
|---|---|
| `test` | a Foundry test in this repository asserts it and passes on a pinned mainnet block; anyone can re-run it |
| `measurement` | a number read from chain state (or produced by a test log) with the exact command recorded |
| `reading` | a statement about source-code semantics taken from the contract's public interface or documentation |
| `hypothesis` | none of the above — must never be presented as a guarantee |

## Claims

| id | claim | evidence | permitted wording | where |
|---|---|---|---|---|
| C1 | A round trip ETH → rETH → ETH never returns more ETH than it took, for 200 random amounts in [0.0001, 10 000] ETH | `test` — `testFuzz_RoundTripNeverProfits`, 200 runs | `enforced on the tested range` | `test/REthAccounting.t.sol` |
| C2 | The same holds for a single 1 ETH round trip | `test` — `test_RoundTripNeverProfits` | `enforced on the tested range` | same |
| C3 | For dust amounts (1 wei … 0.001 ETH) the quoted rETH value never converts back to more than the input | `test` — `testFuzz_SmallAmountRounding`, 200 runs | `enforced on the tested range` | same |
| C4 | The exchange rate did not decrease over a 30-day simulated interval on the pinned block | `test` — `test_ExchangeRateNonDecreasing` | `enforced on the tested interval` | same |
| C5 | The exchange rate is at least 1 ETH per rETH on the pinned block | `test` — `test_ExchangeRateAtLeastParity` | `enforced at the pinned block` | same |
| C6 | When `deposit()` reverts (deposits gated), the call does not take the caller's ETH | `test` — `test_LiveDepositIsGatedOrConserved` | `enforced at the pinned block` | same |
| C7 | When `burn` is unavailable (no deposit-pool liquidity), the harness records it as unavailable rather than as a pass | `test` — `test_BurnPathPaysAtMostRate` (catch branch) | `enforced at the pinned block` | same |
| C8 | Rate at block 26 290 581 is 1.174609541108734450 | `measurement` | `measured` | `METRICS.md` |
| C9 | `getTotalCollateral()` is the liquid buffer, not total staked ETH | `reading` | `according to the contract interface` — **not** a security property | `NOT-CLAIMED.md` |

## Words this repository does not use

- `secure`, `safe`, `verified` as adjectives for rETH or for Rocket Pool.
- `guarantee` / `proves` about anything beyond the specific tests above.
- any statement about the beacon-chain side of the accounting (validators, penalties, withdrawals), because
  the harness does not read beacon state.

`tools/check_claims.py` fails the build if a claim id in this file has no corresponding test in
`test/REthAccounting.t.sol`, or if the test suite does not pass.
