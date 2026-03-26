---
'@balancer-labs/v3-vault': patch
---

Fix BatchRouter revert in ExactOut batch swap paths where addLiquidity is the final step. Multi-step paths ending with a join operation would underflow due to a unit mismatch in BPT settlement tracking.
