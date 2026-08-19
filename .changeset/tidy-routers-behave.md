---
'@balancer-labs/v3-vault': minor
'@balancer-labs/v3-interfaces': minor
---

Composite Liquidity Router changes, described relative to the deployed V2 release. Nested pool operations are reinstated, with explicit per-token wrap/unwrap selection (`addLiquidityUnbalancedNestedPool`, `removeLiquidityProportionalNestedPool`, and their queries). The flat ERC4626 proportional operations now return amounts only, denominated in the tokens the sender actually pays or receives. A token flagged for unwrapping whose proportional share is exactly zero no longer reverts the withdrawal: the buffer is not called, and that token is returned as zero of its underlying. Where the Vault buffer refuses a pool-derived amount as below its minimum wrap amount, the router reverts with `UnwrapAmountTooSmall` or `RequiredWrapAmountTooSmall`, naming the token and the amount, instead of the Vault's token-only error; unrelated reverts are passed through unchanged. As in the deployed release, removals never switch to the Recovery Mode withdrawal path: recovery-mode handling that existed only in unreleased source has been removed, and recovery withdrawals go through the standard Router.
