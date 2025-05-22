// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedLPOracle } from "../WeightedLPOracle.sol";

contract WeightedLPOracleMock is WeightedLPOracle {
    constructor(
        IVault vault,
        IWeightedPool pool,
        AggregatorV3Interface[] memory feeds,
        uint256 version
    ) WeightedLPOracle(vault, pool, feeds, version) {}

    function calculateTVL(int256[] memory prices) external view virtual returns (uint256 tvl) {
        return _calculateTVL(prices);
    }

    function getFeedData() external view returns (int256[] memory prices, uint256 updatedAt) {
        return _getFeedData();
    }

    function getFeeds() external view virtual returns (AggregatorV3Interface[] memory) {
        return _getFeeds(_totalTokens);
    }

    function getFeedTokenDecimalScalingFactors() external view returns (uint256[] memory) {
        return _getFeedTokenDecimalScalingFactors(_totalTokens);
    }

    function getWeights() external view returns (uint256[] memory) {
        return _getWeights(_totalTokens);
    }

    function calculateFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) external view returns (uint256) {
        return _calculateFeedTokenDecimalScalingFactor(feed);
    }
}
