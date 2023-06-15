# <img src="logo.svg" alt="Balancer" height="128px">

# Balancer V3 Monorepo

[![Docs](https://img.shields.io/badge/docs-%F0%9F%93%84-blue)](https://docs.balancer.fi/)
[![CI Status](https://github.com/balancer/balancer-v3-monorepo/workflows/CI/badge.svg)](https://github.com/balancer/balancer-v3-monorepo/actions)
[![License](https://img.shields.io/badge/License-GPLv3-green.svg)](https://www.gnu.org/licenses/gpl-3.0)

This repository contains the Balancer Protocol V3 core smart contracts, including the `Vault` and standard Pools, along with their tests, configuration, and deployment information.

## Structure

This is a Yarn monorepo, with the packages meant to be published in the [`pkg`](./pkg) directory. Newly developed packages may not be published yet.

Active development occurs in this repository, which means some contracts in it might not be production-ready. Proceed with caution.

### Packages

- [`v3-interfaces`](./pkg/interfaces): Solidity interfaces for all contracts.
- [`v3-solidity-utils`](./pkg/solidity-utils): miscellaneous Solidity helpers and utilities used in many different contracts.

## Pre-requisites

The build & test instructions below should work out of the box with Node 18. More specifically, it is recommended to use the LTS version 18.15.0; Node 19 and higher are not supported. Node 18.16.0 has a [known issue](https://github.com/NomicFoundation/hardhat/issues/3877) that makes the build flaky.

Multiple Node versions can be installed in the same system, either manually or with a version manager.
One option to quickly select the suggested Node version is using `nvm`, and running:

```bash
$ nvm use
```

Solidity 0.8.4 or higher is required, as V3 uses custom error messages. We strongly recommend using the latest released version of the Solidity compiler (at least 0.8.18), to incorporate all the latest bug fixes.

## Build and Test

Before any tests can be run, the repository needs to be prepared:

### First time build

```bash
$ yarn # install all dependencies
```

### Regular build

```bash
$ yarn build # compile all contracts
```

Most tests are standalone and simply require installation of dependencies and compilation.

In order to run all tests (including those with extra dependencies), run:

```bash
$ yarn test # run all tests
```

To instead run a single package's tests, run:

```bash
$ cd pkg/<package> # e.g. cd pkg/vault
$ yarn test
```

You can see a sample report of a test run [here](./audits/test-report.md).

### Foundry (Forge) tests

## Static analysis

To run [Slither](https://github.com/crytic/slither) static analyzer, Python 3.8+ is a requirement.

### Installation in virtual environment

This step will create a Python virtual environment with Slither installed. It only needs to be executed once:

```bash
$ yarn slither-install
```

### Run analyzer

```bash
$ yarn slither
```

The analyzer's global settings can be found in `.slither.config.json`.


Some of the analyzer's known findings are already filtered out using [--triage-mode option](https://github.com/crytic/slither/wiki/Usage#triage-mode); the results of the triage can be found in `slither.db.json` files inside each individual workspace.

To run Slither in triage mode:

```bash
$ yarn slither:triage
```

## Security

> Upgradeability | Not Applicable. The system cannot be upgraded.

## Licensing

Most of the Solidity source code is licensed under the GNU General Public License Version 3 (GPL v3): see [`LICENSE`](./LICENSE).

### Exceptions

- All other files, including tests and the [`pvt`](./pvt) directory are unlicensed.
