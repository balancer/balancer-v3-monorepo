// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

// Structure containing LBP-specific parameters. The project token is the one being launched; the sale proceeds will be
// withdrawn in the reserve token. The sale parameters are fixed at deployment: it runs from `startTime` to `endTime`,
// and the weights change from start to end values. If `enableProjectTokenSwapsIn` is set, selling the project token
// "back" into the pool is allowed. Otherwise, users can only purchase project tokens with the reserve currency.
struct LBPParams {
    address owner;
    IERC20 projectToken;
    IERC20 reserveToken;
    uint256 projectTokenStartWeight;
    uint256 reserveTokenStartWeight;
    uint256 projectTokenEndWeight;
    uint256 reserveTokenEndWeight;
    uint256 startTime;
    uint256 endTime;
    bool enableProjectTokenSwapsIn;
}

/**
 * @notice Liquidity Bootstrapping Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in token registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param startWeights Starting weights for the LBP, sorted in token registration order
 * @param endWeights Ending weights for the LBP, sorted in token registration order
 * @param startTime Timestamp of the start of the sale, when all liquidity is present and swaps are enabled
 * @param endTime Timestamp of the end of the sale, when swaps are disabled, and liquidity can be removed
 * @param isProjectTokenSwapInEnabled If true, it is possible to sell the project token back into the pool
 */
struct LBPoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256[] startWeights;
    uint256[] endWeights;
    uint256 startTime;
    uint256 endTime;
    bool isProjectTokenSwapInEnabled;
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
struct LBPoolDynamicData {
    uint256[] balancesLiveScaled18;
    uint256[] normalizedWeights;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool isSwapEnabled;
}

/// @notice Full LBP interface - base pool plus immutable/dynamic field getters.
interface ILBPool is IBasePool {
    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic LBP parameters
     */
    function getLBPoolDynamicData() external view returns (LBPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable LBP parameters
     */
    function getLBPoolImmutableData() external view returns (LBPoolImmutableData memory data);
}
