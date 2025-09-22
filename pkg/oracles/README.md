# <img src="../../logo.svg" alt="Balancer" height="128px">

# Balancer V3 Oracles

This package contains oracle implementations for Balancer V3 pool types that determine the Balancer Pool Token (BPT)
price of each pool. These oracles provide price feeds that are compatible with Chainlink's AggregatorV3Interface,
making them suitable for use in DeFi protocols that require reliable price data.

## Overview

The oracles package provides three main oracle implementations:

- **E-CLP Oracle** (`EclpLPOracle.sol`) - For [Gyro E-CLP Pools](../pool-gyro/contracts/GyroECLPPool.sol)
- **Stable Oracle** (`StableLPOracle.sol`) - For [V3 Stable pools](../pool-stable/contracts/StablePool.sol)
- **Weighted Oracle** (`WeightedLPOracle.sol`) - For [V3 Weighted pools](../pool-weighted/contracts/WeightedPool.sol)

## Architecture

All oracles inherit from `LPOracleBase.sol`, which provides:

- Chainlink AggregatorV3Interface compatibility
- Base functionality for computing Total Value Locked (TVL)
- Token price feed integration
- Standard oracle interface methods

## Features

- **Chainlink Compatible**: All oracles implement the AggregatorV3Interface
- **Multi-Token Support**: Supports pools with up to 8 tokens
- **Price Feed Integration**: Integrates with external price feeds for underlying tokens
- **TVL Calculation**: Computes Total Value Locked for accurate BPT pricing
- **Factory Pattern**: Easy deployment of new oracle instances

## Usage

### Deploying an Oracle

```solidity
// Example: Deploy a Stable pool oracle
StableLPOracleFactory factory = new StableLPOracleFactory(vault);
AggregatorV3Interface[] memory feeds = [token0Feed, token1Feed, token2Feed];
StableLPOracle oracle = factory.create(pool, feeds, 1);
```

### Reading Oracle Data

```solidity
// Get the latest BPT price
(int256 price, uint256 timestamp) = oracle.latestRoundData();
```

## Testing

The package includes comprehensive test suites:

- **Foundry Tests**: Extensive property-based and unit tests
- **Gas Benchmarks**: Performance testing for gas optimization

Run tests with:

```bash
yarn test          # Run all tests
yarn test:forge    # Run Foundry tests only
yarn test:hardhat  # Run Hardhat tests only
```

## Development

### Building

```bash
yarn build         # Compile contracts
yarn compile       # Compile with Hardhat
```

### Code Quality

```bash
yarn lint          # Run all linters
yarn prettier      # Format code
yarn slither       # Run security analysis
```

### Coverage

```bash
yarn coverage      # Run coverage for Foundry tests
yarn coverage:all  # Run coverage for all test suites
```

## Licensing

[GNU General Public License Version 3 (GPL v3)](../../LICENSE).
