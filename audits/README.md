# <img src="../logo.svg" alt="Balancer" height="128px">

# Balancer V3 Audits

This directory the reports of audits performed on Balancer smart contracts by different security firms.
The audits have been conducted before the [Cantina contest](https://cantina.xyz/competitions/949ad7c5-ea14-427d-b10a-54e33cef921b), and all the relevant findings addressed.

| :warning: | Audits are not a guarantee of correctness. Some of the contracts were modified after they were audited.      |
| --------- | :----------------------------------------------------------------------------------------------------------- |

| Scope                             | Firm          | Report                                               |
| --------------------------------- | ------------- | ---------------------------------------------------- |
| Vault, Weighted Pool, Stable Pool | Certora       | [`2024-09-04`](./certora/2024-09-04.pdf)             |
| Vault, Weighted Pool, Stable Pool | Trail Of Bits | [`2024-10-08`](./trail-of-bits/2024-10-08.pdf)       |
| Vault, Weighted Pool, Stable Pool | Spearbit<sup>1</sup> | [`2024-10-04`](./spearbit/2024-10-04.pdf)     |
| Pre-competition v3 codebase       | Cantina<sup>2</sup>  | [`2024-12-17`](./cantina/2024-12-17.pdf)      |
| Post-competition v3 codebase      | Cantina<sup>2</sup>  | [`2024-12-31`](./cantina/2024-12-31.pdf)      |
  
## Addenda
  
<sup>1</sup> Note that 5.2.6 in the Spearbit audit of 2024-10-04 was resolved after the date of the audit. [PR #1113](https://github.com/balancer/balancer-v3-monorepo/pull/1113) replaces the event with explicit add/remove liquidity events, and accounts for swap fees in a separate field.
  
<sup>2</sup> See [this page](https://cantina.xyz/competitions/949ad7c5-ea14-427d-b10a-54e33cef921b) for the description of the competition. The target was a pre-launch version of the codebase at [this commit](https://github.com/balancer/balancer-v3-monorepo/commit/147823666ff6556de2a01c6762ed688ab81a6a33). The follow-up post-competition review was performed on a [fork](https://github.com/cantina-forks/balancer-v3-monorepo/tree/73708b75898a62dac0535f38d1bf471ac0e538c6/) of the code after fixes (from 11/24/24, still pre-launch code). The final deployed v3 codebase contained fixes for all known issues.