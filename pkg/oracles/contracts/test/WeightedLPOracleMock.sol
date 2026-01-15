// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IWrappedBalancerPoolToken } from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolToken.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedLPOracle } from "../WeightedLPOracle.sol";

contract WeightedLPOracleMock is WeightedLPOracle {
    constructor(
        IVault vault_,
        IWrappedBalancerPoolToken wrappedPool,
        AggregatorV3Interface[] memory feeds,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        bool shouldUseBlockTimeForOldestFeedUpdate,
        uint256 version_
    )
        WeightedLPOracle(
            vault_,
            wrappedPool,
            feeds,
            sequencerUptimeFeed,
            uptimeResyncWindow,
            shouldUseBlockTimeForOldestFeedUpdate,
            version_
        )
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) public view returns (uint256) {
        return _computeFeedTokenDecimalScalingFactor(feed);
    }
}
