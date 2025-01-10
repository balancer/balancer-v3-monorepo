// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

/**
 * @notice Gyro 2-CLP Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in token registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param sqrtAlpha Square root of alpha (the lowest price in the price interval of the 2CLP price curve)
 * @param sqrtBeta Square root of beta (the highest price in the price interval of the 2CLP price curve)
 */
struct Gyro2CLPPoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256 sqrtAlpha;
    uint256 sqrtBeta;
}

/**
 * @notice Snapshot of current Gyro 2-CLP Pool data that can change.
 * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode. Withdrawals
 * in Recovery Mode do not make external calls (including those necessary for updating live balances), so if
 * there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
 *
 * @param balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
 * @param tokenRates 18-decimal FP values for rate tokens (e.g., yield-bearing), or FP(1) for standard tokens
 * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
 * @param totalSupply The current total supply of the pool tokens (BPT)
 * @param bptRate The current rate of a pool token (BPT) = invariant / totalSupply
 * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
 * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
 * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
 */
struct Gyro2CLPPoolDynamicData {
    uint256[] balancesLiveScaled18;
    uint256[] tokenRates;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    uint256 bptRate;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
}

interface IGyro2CLPPool is IBasePool {
    /**
     * @notice Gyro 2CLP pool configuration.
     * @param name Pool name
     * @param symbol Pool symbol
     * @param sqrtAlpha Square root of alpha (the lowest price in the price interval of the 2CLP price curve)
     * @param sqrtBeta Square root of beta (the highest price in the price interval of the 2CLP price curve)
     */
    struct GyroParams {
        string name;
        string symbol;
        uint256 sqrtAlpha;
        uint256 sqrtBeta;
    }

    /// @notice The informed alpha is greater than beta.
    error SqrtParamsWrong();

    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic stable pool parameters
     */
    function getGyro2CLPPoolDynamicData() external view returns (Gyro2CLPPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable stable pool parameters
     */
    function getGyro2CLPPoolImmutableData() external view returns (Gyro2CLPPoolImmutableData memory data);
}
