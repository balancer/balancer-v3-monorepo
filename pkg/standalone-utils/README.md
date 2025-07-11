# <img src="../../logo.svg" alt="Balancer" height="128px">

# Balancer V3 Standalone Utils

This package contains standalone utilities that can be used to perform advanced actions in the Balancer V3 protocol.

- [`PriceImpactHelper`](./contracts/PriceImpactHelper.sol) can be used by off-chain clients to calculate price impact for add liquidity unbalanced operations.
- [`StableLPOracle`](./contracts/StableLPOracle.sol) can be used to calculate the TVL of a stable pool. For more information, please refer to this [`document`](./docs/StableOracle.md).
- [`WeightedLPOracle`](./contracts/WeightedLPOracle.sol) can be used to calculate the TVL of a weighted pool.

[GNU General Public License Version 3 (GPL v3)](../../LICENSE).
