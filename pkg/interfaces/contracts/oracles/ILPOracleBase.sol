// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILPOracleBase {
    /// @notice A price feed has decimals greater than the maximum allowed.
    error UnsupportedDecimals();

    /// @notice Oracle prices must be greater than zero to prevent zero or negative TVL values.
    error InvalidOraclePrice();

    /// @notice The vault is unlocked for an oracle that requires a locked Vault to guarantee non-manipulable prices.
    error VaultIsUnlocked();

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
     * @dev The feeds might have different update frequencies; e.g., one updates hourly, and another daily.
     * Some use cases may require sophisticated analysis, so `updatedAt` returns all values.
     *
     * @return prices An array of latest prices from the feeds
     * @return updatedAt An array of timestamps corresponding to the last update of each feed
     */
    function getFeedData() external view returns (int256[] memory prices, uint256[] memory updatedAt);

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

    /**
     * @notice Getter for the `latestRoundData` behavior flag.
     * @dev If set, `latestRoundData` returns the current time for `updatedAt`, instead of calculating the minimum
     * update time over all the feeds (i.e., using the update time of the "oldest" / most stale feed).
     *
     * @return shouldUseBlockTimeForOldestFeedUpdate The feed update flag setting
     */
    function getShouldUseBlockTimeForOldestFeedUpdate()
        external
        view
        returns (bool shouldUseBlockTimeForOldestFeedUpdate);

    /**
     * @notice Getter for the `revertIfVaultUnlocked` behavior flag.
     * @dev If set, operations requiring calculation of the TVL will revert if the Vault is unlocked (i.e.,
     * in the middle of an operation). This guarantees that the BPT balance is "real," and not transient, which would
     * make the result manipulable in cases where no other protective mechanisms are available (such as using wrapped
     * BPT, or imposing limits in the lending protocol).
     *
     * @return shouldRevertIfVaultUnlocked The feed update flag setting
     */
    function getShouldRevertIfVaultUnlocked() external view returns (bool shouldRevertIfVaultUnlocked);
}
