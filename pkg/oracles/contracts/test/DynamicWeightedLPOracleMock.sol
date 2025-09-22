// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";

import { DynamicWeightedLPOracle } from "../DynamicWeightedLPOracle.sol";

contract DynamicWeightedLPOracleMock is DynamicWeightedLPOracle {
    constructor(
        IVault vault_,
        IWeightedPool pool_,
        AggregatorV3Interface[] memory feeds,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        uint256 version_
    ) DynamicWeightedLPOracle(vault_, pool_, feeds, sequencerUptimeFeed, uptimeResyncWindow, version_) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function computeFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) public view returns (uint256) {
        return _computeFeedTokenDecimalScalingFactor(feed);
    }
}
