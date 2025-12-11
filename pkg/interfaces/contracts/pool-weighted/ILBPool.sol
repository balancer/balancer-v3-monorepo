// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILBPCommon } from "./ILBPCommon.sol";

/**
 * @notice Structure containing LBP-specific parameters.
 * @dev See `LBPCommonParams` in ILBPCommon.sol for general parameters. Seedless LBPs do not require any reserve tokens
 * for initialization. However, we do need the amount that *would be* required for a non-seedless LBP, in order to set
 * the initial price properly. Since we cannot intercept initialization (which goes directly through the Vault), this
 * parameter must be set at deployment time. When calling initialize, the caller must specify 0 reserve tokens.
 *
 * @param projectTokenStartWeight The project token weight at the start of the sale (normally higher than the reserve)
 * @param reserveTokenStartWeight The reserve token weight at the start of the sale (normally lower than the project)
 * @param projectTokenEndWeight The project token weight at the end of the sale (should go down over time)
 * @param reserveTokenEndWeight The reserve token weight at the end of the sale (should go up over time)
 * @param reserveTokenVirtualBalance The amount of reserve tokens needed to set the initial price; 0 for non-seedless
 */
struct LBPParams {
    uint256 projectTokenStartWeight;
    uint256 reserveTokenStartWeight;
    uint256 projectTokenEndWeight;
    uint256 reserveTokenEndWeight;
    uint256 reserveTokenVirtualBalance;
}

/**
 * @notice Snapshot of current Weighted Pool data that can change.
 * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode. Withdrawals
 * in Recovery Mode do not make external calls (including those necessary for updating live balances), so if
 * there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
 *
 * @param balancesLiveScaled18 18-decimal FP token balances, sorted in token registration order
 * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
 * @param totalSupply The current total supply of the pool tokens (BPT)
 * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
 * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
 * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
 * @param isSwapEnabled If true, the sale is ongoing, and swaps are enabled (unless the pool is paused)
 * @param normalizedWeights Current token weights, sorted in token registration order
 */
struct LBPoolDynamicData {
    // Common LBPool Dynamic Data parameters
    uint256[] balancesLiveScaled18;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool isSwapEnabled;
    // LBPool-specific parameters
    uint256[] normalizedWeights;
}

/**
 * @notice Liquidity Bootstrapping Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in token registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param startTime Timestamp of the start of the sale, when all liquidity is present and swaps are enabled
 * @param endTime Timestamp of the end of the sale, when swaps are disabled, and liquidity can be removed
 * @param projectTokenIndex The index of token (in `tokens`) being distributed through the sale
 * @param reserveTokenIndex The index of the token (in `tokens`) used to purchase project tokens
 * @param isProjectTokenSwapInBlocked If true, it is impossible to sell the project token back into the pool
 * @param startWeights Starting weights for the LBP, sorted in token registration order
 * @param endWeights Ending weights for the LBP, sorted in token registration order
 * @param reserveTokenVirtualBalance The reserve token virtual balance, in native decimals. Non-zero for seedless LBPs
 * @param migrationRouter The address of the router used for migration to a Weighted Pool after the sale
 * @param lockDurationAfterMigration The duration for which the BPT will be locked after migration
 * @param bptPercentageToMigrate The percentage of the BPT to migrate from the LBP to the new weighted pool
 * @param migrationWeightProjectToken The weight of the project token
 * @param migrationWeightReserveToken The weight of the reserve token
 */
struct LBPoolImmutableData {
    // Common LBPool immutable parameters
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256 startTime;
    uint256 endTime;
    uint256 projectTokenIndex;
    uint256 reserveTokenIndex;
    bool isProjectTokenSwapInBlocked;
    // LBPool-specific parameters (weight transitions / virtual balance for seedless)
    uint256[] startWeights;
    uint256[] endWeights;
    uint256 reserveTokenVirtualBalance;
    // Migration parameters (if migrationRouter == address(0), the pool does not support migration).
    address migrationRouter;
    uint256 lockDurationAfterMigration;
    uint256 bptPercentageToMigrate;
    uint256 migrationWeightProjectToken;
    uint256 migrationWeightReserveToken;
}

/// @notice Interface for standard LBPools - base LBP functions, plus immutable/dynamic field getters.
interface ILBPool is ILBPCommon {
    /// @notice If the LBP is seedless, the caller must initialize with 0 reserve tokens.
    error SeedlessLBPInitializationWithNonZeroReserve();

    /**
     * @notice The amount out of the reserve token cannot exceed the real balance.
     * @dev Both amounts are given as 18-decimal FP values (not in native decimals).
     * @param reserveTokenAmountOut The amount of reserve tokens requested
     * @param reserveTokenRealBalance The amount of reserve tokens actually available
     */
    error InsufficientRealReserveBalance(uint256 reserveTokenAmountOut, uint256 reserveTokenRealBalance);

    /**
     * @notice Return start time and end time, as well as starting and ending weights as arrays.
     * @dev The current weights should be retrieved via `getNormalizedWeights()`.
     * @return startTime The starting timestamp of any ongoing weight change
     * @return endTime The ending timestamp of any ongoing weight change
     * @return startWeights The "initial" weights, sorted in token registration order
     * @return endWeights The "destination" weights, sorted in token registration order
     */
    function getGradualWeightUpdateParams()
        external
        view
        returns (uint256 startTime, uint256 endTime, uint256[] memory startWeights, uint256[] memory endWeights);

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

    /**
     * @notice Get the reserve token virtual balance, in native token decimals.
     * @dev This is the "offset" applied to set the initial price for a seedless LBP, without requiring any reserve
     * tokens on initialization. This will be zero if the LBP is not seedless.
     *
     * @return reserveTokenVirtualBalance The virtual balance of reserve tokens
     */
    function getReserveTokenVirtualBalance() external view returns (uint256 reserveTokenVirtualBalance);
}
