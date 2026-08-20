# Known issues

Some of the active deployments have known issues that are not security issues and are **not** eligible for a bug bounty.

This list might be updated over time with new findings and is not to be comprehensive or complete. Bug bounty reports pointing out these issues will be automatically closed.

## Stable surge - exact in / exact out equivalence

The way the surge fees are computed in the stable surge hook is an approximation that keeps the computation _simple_.
For big swaps and large max surge swap fee, the approximation breaks exact in / exact out equivalence. In other words:

```
swap_in(Ai) = Ao 
swap_out(Ao) != Ai
```

Since this happens only in extreme cases that are not relevant in practice, simplicity is preferred over accuracy in this case.
By no means this constitutes a security issue: any error computing a dynamic swap fee above the static swap fee percentage cannot lead to theft of funds.

## Protocol fee controller - fee split rounding

When the aggregate fees are split between protocol and pool creator, rounding effects can make the transaction revert under specific circumstances.

These typically happen when the pool creator fee is low, and low amount of fees are collected.

In this case, the cost of fixing an obscure edge case and migrating the fee controller is not justified by the potential impact. In practice:
- Most pools do not use pool creator fees
- While the fee split to trigger the problem is technically valid, fee splits in practice tend to use larger numbers
- Fees are collected after they reach certain threshold, not right after each operation generates any amount of fees

## Gyro E-CLP - derived parameter consistency

An E-CLP pool is parameterized by five primary values (alpha, beta, c, s, lambda) and nine derived values that are computed off-chain and supplied by the pool creator at deployment. The contract validates that every supplied value is within its permitted range, but does not verify that the derived values were actually computed from the primary values; the comment on `GyroECLPMath.validateDerivedParamsLimits` says so explicitly. Verifying full consistency on-chain would require reproducing transcendental math that the contract deliberately leaves off-chain.

All fourteen values are immutable once the pool is created. No existing pool can be affected, and no pool created by anyone else can be affected: the only pool that can carry an inconsistent parameter set is one whose own creator supplied it. Such a pool trades on a different curve than its parameters describe, can quote and display a price range that does not match its actual trading behavior, and can lose value to whoever trades against it; the loss falls on that pool's own liquidity providers, starting with the creator who funded it. The canonical deployment tooling produces consistent parameter sets.

Deployed contracts are immutable, and no change to this validation is currently planned. New deployments are monitored, and pools carrying an inconsistent parameter set are dropped by the subgraph and blacklisted (i.e., excluded from the official UI and aggregators). Reports that an inconsistent, creator-supplied parameter set can misprice a pool, lose value to traders, or advertise a wrong price range are known issues under this list; they also fall under the program's existing exclusion for vulnerabilities that require interaction with a deliberately malformed pool.
