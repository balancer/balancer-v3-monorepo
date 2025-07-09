// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILPOracleBase {
    // A price feed has decimals greater than the maximum allowed.
    error UnsupportedDecimals();

    /**
     * @notice Calculates the TVL based on the provided prices.
     * @dev Prices are defined the same way as in the oracle feed, and scaled to 18-decimal FP values.
     * @param prices An array of prices for the tokens in the pool, sorted in token registration order
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
     * @return feeds An array of AggregatorV3Interface instances representing the feeds
     */
    function getFeeds() external view returns (AggregatorV3Interface[] memory feeds);

    /**
     * @notice Gets the decimal scaling factors for each feed token.
     * @return feedScalingFactors An array of scaling factors corresponding to each feed
     */
    function getFeedTokenDecimalScalingFactors() external view returns (uint256[] memory feedScalingFactors);

    /**
     * @notice Gets the tokens in the pool.
     * @return tokens An array of token addresses, sorted in token registration order
     */
    function getPoolTokens() external view returns (IERC20[] memory tokens);
}
