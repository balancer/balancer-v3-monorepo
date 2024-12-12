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
| Vault, Weighted Pool, Stable Pool | Spearbit*     | [`2024-10-04`](./spearbit/2024-10-04.pdf)            |

## Addenda
* Note that 5.2.6 in the Spearbit audit of 2024-10-04 was resolved after the date of the audit. [PR #1113](https://github.com/balancer/balancer-v3-monorepo/pull/1113) replaces the event with explicit add/remove liquidity events, and accounts for swap fees in a separate field.
