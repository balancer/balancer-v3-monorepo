# Security policy

## Reporting a vulnerability

Do not open a public issue, pull request, or discussion for a suspected vulnerability in these contracts. Public disclosure before a fix is deployed puts user funds at risk and can affect eligibility under the bounty program's terms.

Report it through the Balancer bug bounty program on Immunefi: https://immunefi.com/bounty/balancer/

The program page is the authoritative source for the assets in scope, the impacts that are rewarded, the reward amounts, and what a submission must contain. Nothing in this file changes those terms, and where this file and the program page differ, the program page governs.

## Scope

This repository holds the Balancer V3 Vault, the routers, the pool types, and the hooks. The program lists specific deployed contract addresses as its assets in scope, so the presence of code in this repository does not by itself put it in scope. Code that is not deployed is not an asset, and that includes mock contracts, everything under a `test` directory, and anything on an unmerged branch or in an open pull request.

## What will be closed

The following account for most of what arrives. They are listed here so you can avoid spending time on them.

**Anything that requires an explicitly malicious pool, hook, router, or rate provider.** The program excludes "vulnerabilities that require the user to interact with explicitly malicious routers, pools, hooks or rate providers", because "introducing such vulnerabilities in a permissionless protocol is both trivial and impossible to prevent". Balancer V3 is permissionless: anyone can deploy a pool or a hook, and a hostile one harms only the people who choose to use it. Such a report is in scope only if it demonstrates harm to the Vault or to users outside the attacker's own pool.

**Anything that requires a non-standard ERC20 token.** Tokens with transfer fees, rebasing supply, streaming mechanics, or multiple entry points fall outside the assumptions these contracts are written against.

**Issues already documented as known.** See `audits/WONTFIX.md` in this repository, which states that reports pointing at a listed issue are closed automatically, and the published audit reports under `audits/`.

**Automated scanner or language model output.** A report produced by a scanner or a model, carrying no working proof of concept and no demonstrated impact, will be closed. If the submission links to a fuller writeup, confirm the link resolves before sending it.

**Findings with no path to an exploit.** Gas optimizations, code style, input validation that nothing reachable can violate, concerns about the authority of documented permissioned roles acting within it, and theoretical observations with no concrete route to loss are not vulnerabilities under this program.

## Public issues

A public issue reporting a suspected vulnerability will be closed without triage and redirected to the program above.
