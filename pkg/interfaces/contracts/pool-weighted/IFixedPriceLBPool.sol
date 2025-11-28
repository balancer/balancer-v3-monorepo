// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILBPCommon } from "./ILBPCommon.sol";

/**
 * @notice Liquidity Bootstrapping Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in token registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param startTime Timestamp of the start of the sale, when all liquidity is present and swaps are enabled
 * @param endTime Timestamp of the end of the sale, when swaps are disabled, and liquidity can be removed
 * @param projectTokenIndex The index of token (in `tokens`) being distributed through the sale
 * @param reserveTokenIndex The index of the token (in `tokens`) used to purchase project tokens
 * @param projectTokenRate The price of the project token in terms of the reserve
 */
struct FixedPriceLBPoolImmutableData {
    // Common LBPool immutable parameters
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256 startTime;
    uint256 endTime;
    uint256 projectTokenIndex;
    uint256 reserveTokenIndex;
    // Fixed price LBP immutable parameters
    uint256 projectTokenRate;
}

/**
 * @notice Snapshot of current Weighted Pool data that can change.
 * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode. Withdrawals
 * in Recovery Mode do not make external calls (including those necessary for updating live balances), so if
 * there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
 *
 * @param balancesLiveScaled18 18-decimal FP token balances, sorted in token registration order
 * @param normalizedWeights Current token weights, sorted in token registration order
 * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
 * @param totalSupply The current total supply of the pool tokens (BPT)
 * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
 * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
 * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
 * @param isSwapEnabled If true, the sale is ongoing, and swaps are enabled (unless the pool is paused)
 */
struct FixedPriceLBPoolDynamicData {
    // Common LBPool Dynamic Data parameters
    uint256[] balancesLiveScaled18;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool isSwapEnabled;
}

/**
 * @notice Interface for fixed price LBPools - base LBP functions, plus immutable/dynamic field getters.
 * @dev The "price" of a fixed price LBP is represented by a `projectTokenRate`: this corresponds to the number of
 * reserve tokens required to purchase one project token. For instance, if we want to sell a million tokens to raise
 * $100k USDC, the rate would be 0.1 (10 cents), or 1e17.
 *
 */
interface IFixedPriceLBPool is ILBPCommon {
    /// @notice An initialization amount is invalid (e.g., zero token balance, or non-zero reserve).
    error InvalidInitializationAmount();

    /// @notice The token sale price cannot be zero.
    error InvalidProjectTokenRate();

    /// @notice All fixed price LBPools are "buy only;" token swaps in are not supported.
    error TokenSwapsInUnsupported();

    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic LBP parameters
     */
    function getFixedPriceLBPoolDynamicData() external view returns (FixedPriceLBPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable LBP parameters
     */
    function getFixedPriceLBPoolImmutableData() external view returns (FixedPriceLBPoolImmutableData memory data);

    /**
     * @notice Get the project token rate (price) in terms of reserve tokens.
     * @dev This is included in the immutable data, but also added here for convenience.
     */
    function getProjectTokenRate() external view returns (uint256);
}
