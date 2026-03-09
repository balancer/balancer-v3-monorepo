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

It is simply **not** worth fixing and migrating the fee controller over this. In practice:
- Most pools do not use pool creator fees
- While the fee split to trigger the problem is technically valid, fee splits in practice tend to use larger numbers
- Fees are collected after they reach certain threshold, not right after each operation generates any amount of fees