// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IWrappedBalancerPoolToken } from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolToken.sol";
import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/oracles/IWeightedLPOracle.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { LPOracleFactoryBase } from "./LPOracleFactoryBase.sol";
import { WeightedLPOracle } from "./WeightedLPOracle.sol";

/**
 * @notice Factory for deploying and managing Weighted Pool oracles.
 */
contract WeightedLPOracleFactory is LPOracleFactoryBase {
    constructor(
        IVault vault,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        string memory factoryVersion,
        uint256 oracleVersion
    ) LPOracleFactoryBase(vault, sequencerUptimeFeed, uptimeResyncWindow, factoryVersion, oracleVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _create(
        IVault vault,
        IWrappedBalancerPoolToken wrappedPool,
        bool shouldUseBlockTimeForOldestFeedUpdate,
        AggregatorV3Interface[] memory feeds
    ) internal override returns (ILPOracleBase) {
        return
            ILPOracleBase(
                new WeightedLPOracle(
                    vault,
                    wrappedPool,
                    feeds,
                    _sequencerUptimeFeed,
                    _uptimeResyncWindow,
                    shouldUseBlockTimeForOldestFeedUpdate,
                    _oracleVersion
                )
            );
    }
}
