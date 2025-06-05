// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IWeightedLPOracle {
    /**
     * @notice Calculates the tvl based on the provided prices.
     * @dev Prices are defined the same way as in the oracle feed, and scaled to 18-decimal FP values.
     * @param prices An array of prices for the tokens in the pool
     * @return tvl TVL calculated from the prices and current weights
     */
    function calculateTVL(int256[] memory prices) external view returns (uint256 tvl);

    /**
     * @notice Gets the latest feed data.
     * @return prices An array of latest prices from the feeds
     * @return updatedAt The timestamp of the last update
     */
    function getFeedData() external view returns (int256[] memory prices, uint256 updatedAt);

    /**
     * @notice Gets the list of feeds used by the oracle.
     * @return An array of AggregatorV3Interface instances representing the feeds.
     */
    function getFeeds() external view returns (AggregatorV3Interface[] memory);

    /**
     * @notice Gets the decimal scaling factors for each feed token.
     * @return An array of scaling factors corresponding to each feed.
     */
    function getFeedTokenDecimalScalingFactors() external view returns (uint256[] memory);

    /**
     * @notice Gets the current weights of the tokens in the pool.
     * @return An array of weights corresponding to each token in the pool.
     */
    function getWeights() external view returns (uint256[] memory);

    /**
     * @notice Calculates the decimal scaling factor for a specific feed.
     * @param feed The AggregatorV3Interface instance for which to calculate the scaling factor.
     * @return The scaling factor as a uint256.
     */
    function calculateFeedTokenDecimalScalingFactor(AggregatorV3Interface feed) external view returns (uint256);
}
