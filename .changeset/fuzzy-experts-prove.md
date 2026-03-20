---
'@balancer-labs/v3-vault': patch
---

Fix ETH locked in CompositeLiquidityRouter when removeLiquidityProportionalFromERC4626Pool is called with msg.value. The remove-liquidity hook was missing a  

