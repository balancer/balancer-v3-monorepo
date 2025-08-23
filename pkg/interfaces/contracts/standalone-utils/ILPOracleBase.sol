// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILPOracleBase {
    /// @notice A price feed has decimals greater than the maximum allowed.
    error UnsupportedDecimals();

    /// @notice Oracle prices must be greater than zero to prevent zero or negative TVL values.
    error InvalidOraclePrice();

    /**
     * @notice Calculates the TVL based on the current prices.
     * @return tvl TVL (total value locked) calculated from the prices and other pool data
     */
    function computeTVL() external view returns (uint256 tvl);

    /**
     * @notice Calculates the TVL based on the given prices.
     * @dev Prices are defined the same way as in the oracle feed, and scaled to 18-decimal FP values.
     * Since it accepts arbitrary prices, this version isn't for use in production, but is a useful
     * utility function for testing, integration, and simulation.
     *
     * @param prices An array of prices for the tokens in the pool, sorted in token registration order
     * @return tvl TVL (total value locked) calculated from the prices and other pool data
     */
    function computeTVLGivenPrices(int256[] memory prices) external view returns (uint256 tvl);

    /**
     * @notice Gets the latest feed data.
     * @dev The feeds might have different update frequencies; e.g., one updates hourly, and another daily. For most
     * applications, the "oldest" (i.e., least up-to-date) timestamp is a common way to represent the overall state,
     * so it is returned for convenience as `minUpdatedAt`. However, some use cases may require more sophisticated
     * analysis, so `updatedAt` returns all values.
     *
     * @return prices An array of latest prices from the feeds
     * @return updatedAt An array of timestamps corresponding to the last update of each feed
     * @return minUpdatedAt The oldest / least recent timestamp (the value returned by `latestRoundData`)
     */
    function getFeedData()
        external
        view
        returns (int256[] memory prices, uint256[] memory updatedAt, uint256 minUpdatedAt);

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
