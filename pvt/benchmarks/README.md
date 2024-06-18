# <img src="../../logo.svg" alt="Balancer" height="128px">

# Balancer V3 Benchmarks

This package contains various benchmarks for the Balancer V3 platform.

## Overview

### Gas report

To get the report that averages the result of every test, execute:

```console
$ yarn gas
```

To run specific tests, use `--match-test` or `--match-contract` specifier; for example:

```console
$ yarn gas --match-test testSwapExactInWithoutRate
```

## Licensing

[GNU General Public License Version 3 (GPL v3)](../../LICENSE).
