// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

/**
 * @notice Full state of any ongoing or scheduled amplification parameter update.
 * @dev If there is an ongoing or scheduled update, `startTime` and/or `endTime` will be in the future.
 * On initialization, startTime == endTime, and both startValue and endValue will reflect the initial amp setting.
 *
 * @return startValue The amplification parameter at the start of the update
 * @return endValue The final value of the amplification parameter
 * @return startTime The timestamp when the update begins
 * @return endTime The timestamp when the update ends
 */
struct AmplificationState {
    uint64 startValue;
    uint64 endValue;
    uint32 startTime;
    uint32 endTime;
}

/**
 * @notice Stable Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in pool registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param amplificationParameterPrecision Scaling factor used to increase the precision of calculations involving the
 * `amplificationParameter`. (See StableMath `MIN_AMP`, `MAX_AMP`, `AMP_PRECISION`)
 */
struct StablePoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256 amplificationParameterPrecision;
}

/**
 * @notice Snapshot of current Stable Pool data that can change.
 * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode. Withdrawals
 * in Recovery Mode do not make external calls (including those necessary for updating live balances), so if
 * there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
 *
 * @param balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
 * @param tokenRates 18-decimal FP values for rate tokens (e.g., yield-bearing), or FP(1) for standard tokens
 * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
 * @param totalSupply The current total supply of the pool tokens (BPT)
 * @param bptRate The current rate of a pool token (BPT) = invariant / totalSupply
 * @param amplificationParameter Controls the "flatness" of the invariant curve. higher values = lower slippage,
 * and assumes prices are near parity. lower values = closer to the constant product curve (e.g., more like a
 * weighted pool). This has higher slippage, and accommodates greater price volatility. Note that this is the raw
 * amp value, not multiplied by `StableMath.AMP_PRECISION`
 * @param startValue The amplification parameter at the start of an update
 * @param endValue The final value of the amplification parameter
 * @param startTime The timestamp when the update begins
 * @param endTime The timestamp when the update ends
 * @param isAmpUpdating True if an amplification parameter update is in progress
 * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
 * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
 * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
 */
struct StablePoolDynamicData {
    uint256[] balancesLiveScaled18;
    uint256[] tokenRates;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    uint256 bptRate;
    uint256 amplificationParameter;
    uint256 startValue;
    uint256 endValue;
    uint32 startTime;
    uint32 endTime;
    bool isAmpUpdating;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
}

/// @notice Full Stable Pool interface.
interface IStablePool is IBasePool {
    /**
     * @dev Begins changing the amplification parameter to `rawEndValue` over time. The value will change linearly until
     * `endTime` is reached, when it will equal `rawEndValue`.
     *
     * NOTE: Internally, the amplification parameter is represented using higher precision. The values returned by
     * `getAmplificationParameter` have to be corrected to account for this when comparing to `rawEndValue`.
     */
    function startAmplificationParameterUpdate(uint256 rawEndValue, uint256 endTime) external;

    /// @dev Stops the amplification parameter change process, keeping the current value.
    function stopAmplificationParameterUpdate() external;

    /**
     * @notice Get all the amplification parameters.
     * @return value Current amplification parameter value (could be in the middle of an update)
     * @return isUpdating True if an amplification parameter update is in progress
     * @return precision The raw value is multiplied by this number for greater precision during updates
     */
    function getAmplificationParameter() external view returns (uint256 value, bool isUpdating, uint256 precision);

    /**
     * @notice Get the full state of any ongoing or scheduled amplification parameter update.
     * @return amplificationState Struct containing the update data
     */
    function getAmplificationState() external view returns (AmplificationState memory amplificationState);

    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic stable pool parameters
     */
    function getStablePoolDynamicData() external view returns (StablePoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable stable pool parameters
     */
    function getStablePoolImmutableData() external view returns (StablePoolImmutableData memory data);
}
