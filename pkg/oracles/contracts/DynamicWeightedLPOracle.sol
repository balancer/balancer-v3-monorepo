// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/oracles/IWeightedLPOracle.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedLPOracle } from "./WeightedLPOracle.sol";

/**
 * @notice Oracle for weighted pools with dynamic weight fetching.
 * @author Amped Finance https://github.com/AmpedFinance
 * @dev This oracle fetches weights dynamically from the pool instead of storing them at deployment.
 * This enables proper TVL calculation for pools where weights may change over time, such as
 * Liquidity Bootstrapping Pools (LBPs) or other dynamic weight pool implementations.
 */
contract DynamicWeightedLPOracle is IWeightedLPOracle, WeightedLPOracle {
    /// @dev Constructor delegates to parent - weights will be dynamically fetched via _getWeights override.
    constructor(
        IVault vault_,
        IWeightedPool pool_,
        AggregatorV3Interface[] memory feeds,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        uint256 version_
    ) WeightedLPOracle(vault_, pool_, feeds, sequencerUptimeFeed, uptimeResyncWindow, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Get current normalized weights from the pool dynamically.
     * @dev Overrides the parent implementation to fetch weights from the pool in real-time
     * instead of using cached weights from deployment time.

     * @return weights Array of current normalized weights from the pool
     */
    function _getWeights() internal view override returns (uint256[] memory) {
        return IWeightedPool(address(pool)).getNormalizedWeights();
    }
}
