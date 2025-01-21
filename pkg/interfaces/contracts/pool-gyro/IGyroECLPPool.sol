// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

/**
 * @notice Gyro E-CLP Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in token registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param paramsAlpha Lower price limit. alpha > 0
 * @param paramsBeta Upper price limit. beta > alpha > 0
 * @param paramsC `c = cos(-phi) >= 0`, rounded to 18 decimals. Phi is the rotation angle of the ellipse
 * @param paramsS `s = sin(-phi) >= 0`, rounded to 18 decimals. Phi is the rotation angle of the ellipse
 * @param paramsLambda Stretching factor, lambda >= 1. When lambda == 1, we have a perfect circle
 * @param tauAlphaX
 * @param tauAlphaY
 * @param tauBetaX
 * @param tauBetaY
 * @param u from (A chi)_y = lambda * u + v
 * @param v from (A chi)_y = lambda * u + v
 * @param w from (A chi)_x = w / lambda + z
 * @param z from (A chi)_x = w / lambda + z
 * @param dSq error in c^2 + s^2 = dSq, used to correct errors in c, s, tau, u,v,w,z calculations
 */
struct GyroECLPPoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    int256 paramsAlpha;
    int256 paramsBeta;
    int256 paramsC;
    int256 paramsS;
    int256 paramsLambda;
    int256 tauAlphaX;
    int256 tauAlphaY;
    int256 tauBetaX;
    int256 tauBetaY;
    int256 u;
    int256 v;
    int256 w;
    int256 z;
    int256 dSq;
}

/**
 * @notice Snapshot of current Gyro E-CLP Pool data that can change.
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
struct GyroECLPPoolDynamicData {
    uint256[] balancesLiveScaled18;
    uint256[] tokenRates;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    uint256 bptRate;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
}

interface IGyroECLPPool is IBasePool {
    event ECLPParamsValidated(bool paramsValidated);
    event ECLPDerivedParamsValidated(bool derivedParamsValidated);

    /**
     * @notice Gyro E-CLP pool configuration.
     * @param name Pool name
     * @param symbol Pool symbol
     * @param eclpParams Parameters to configure the E-CLP pool, with 18 decimals
     * @param derivedEclpParams Parameters calculated off-chain based on eclpParams. 38 decimals for higher precision
     */
    struct GyroECLPPoolParams {
        string name;
        string symbol;
        EclpParams eclpParams;
        DerivedEclpParams derivedEclpParams;
        string version;
    }

    /**
     * @notice Struct containing parameters to build the ellipse which describes the pricing curve of an E-CLP pool.
     * @dev Note that all values are positive and could consist of uint's. However, this would require converting to
     * int numerous times because of int operations, so we store them as int to simplify the code.
     *
     * @param alpha Lower price limit. alpha > 0
     * @param beta Upper price limit. beta > alpha > 0
     * @param c `c = cos(-phi) >= 0`, rounded to 18 decimals. Phi is the rotation angle of the ellipse
     * @param s `s = sin(-phi) >= 0`, rounded to 18 decimals. Phi is the rotation angle of the ellipse
     * @param lambda Stretching factor, lambda >= 1. When lambda == 1, we have a perfect circle
     */
    struct EclpParams {
        int256 alpha;
        int256 beta;
        int256 c;
        int256 s;
        // Invariant: c^2 + s^2 == 1, i.e., the point (c, s) is normalized.
        // Due to rounding, this may not be 1. The term dSq in DerivedParams corrects for this in extra precision
        int256 lambda;
    }

    /**
     * @notice Struct containing parameters calculated based on EclpParams, off-chain.
     * @dev All these parameters can be calculated using the EclpParams, but they're calculated off-chain to save gas
     * and increase the precision. Therefore, the numbers are stored with 38 decimals precision. Please refer to
     * https://docs.gyro.finance/gyroscope-protocol/technical-documents, document "E-CLP high-precision
     * calculations.pdf", for further explanations on how to obtain the parameters below.
     *
     * @param tauAlpha
     * @param tauBeta
     * @param u from (A chi)_y = lambda * u + v
     * @param v from (A chi)_y = lambda * u + v
     * @param w from (A chi)_x = w / lambda + z
     * @param z from (A chi)_x = w / lambda + z
     * @param dSq error in c^2 + s^2 = dSq, used to correct errors in c, s, tau, u,v,w,z calculations
     */
    struct DerivedEclpParams {
        Vector2 tauAlpha;
        Vector2 tauBeta;
        int256 u;
        int256 v;
        int256 w;
        int256 z;
        int256 dSq;
    }

    /// @notice Struct containing a 2D vector.
    struct Vector2 {
        int256 x;
        int256 y;
    }

    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic stable pool parameters
     */
    function getGyroECLPPoolDynamicData() external view returns (GyroECLPPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable stable pool parameters
     */
    function getGyroECLPPoolImmutableData() external view returns (GyroECLPPoolImmutableData memory data);
}
