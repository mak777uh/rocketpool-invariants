# What this repository refuses to claim

The value of a witness comes from the list of things it does *not* assert. This file is that list, and it is
part of the artifact on purpose.

## Not claimed about rETH

| not claimed | why |
|---|---|
| "rETH accounting is safe" | seven tests on three blocks are a witness, not an audit |
| "funds are conserved" in general | only the specific round-trip and dust properties in `CLAIMS.md` are asserted |
| "the exchange rate can never fall" | the test covers a simulated 30-day interval on a pinned block with no penalty events; a validator penalty or a slashing event is outside the harness |
| "collateral covers all minted rETH" | `getTotalCollateral()` returns the liquid buffer (deposit pool), not the staked ETH backing rETH; comparing it to `totalSupply × rate` is a category error and an early version of this harness made exactly that mistake |
| "deposits and burns work" | on all three pinned blocks `deposit()` is gated and `burn` is unavailable; the harness asserts the *safety* of the gated state, not the correctness of the open state |
| "the contract is free of bugs" | absence of a counterexample in 200 fuzz runs is evidence, not proof |

## Not covered technically

- **Beacon-chain accounting**: validator balances, entry/exit queues, penalties, withdrawal credentials.
- **Oracle/report path**: how the protocol's oDAO reports balances and how the rate is updated from them.
- **RPL bond and node-operator collateral**: the boundary where user funds meet operator collateral is
  described in the grant proposal, not asserted here.
- **Governance and upgrade risk**: the contracts are upgradeable behind a storage contract; the harness reads
  one deployment at one block.
- **Front-running / MEV**: the harness calls view functions and records states; it does not model ordering.

## Wording discipline

`CLAIMS.md` assigns each statement an evidence type. The words `PROVEN`, `ENFORCED_TESTED` and `guarantee`
are only permitted where the evidence is `test` on the exact range that was tested; everywhere else the
permitted wording is `measured`, `according to the interface`, or `hypothesis`.
