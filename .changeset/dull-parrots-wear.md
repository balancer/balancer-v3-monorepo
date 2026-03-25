---
'@balancer-labs/v3-pool-hooks': patch
---

Fix StableSurgeMedianMath.findMedian in-place sort mutation. calculateImbalance now deletes the input array after use, converting potential silent misuse into a revert.
