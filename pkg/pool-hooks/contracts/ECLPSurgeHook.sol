// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { SignedFixedPoint } from "@balancer-labs/v3-pool-gyro/contracts/lib/SignedFixedPoint.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { GyroECLPMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroECLPMath.sol";

import { SurgeHookCommon } from "./SurgeHookCommon.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a "surge" fee on trades that unbalance the pool beyond the threshold.
 */
contract ECLPSurgeHook is SurgeHookCommon {
    using SignedFixedPoint for int256;
    using FixedPoint for uint256;
    using SafeCast for *;

    /**
     * @notice The rotation angle is too small or too large for the surge hook to be used.
     * @dev The surge hook accepts angles from 30 to 60 degrees. Outside of this range, the computation of the peak
     * price cannot be approximated by sine/cosine.
     */
    error InvalidRotationAngle();

    /**
     * @notice A new `ECLPSurgeHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event ECLPSurgeHookRegistered(address indexed pool, address indexed factory);

    constructor(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) SurgeHookCommon(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                IHooks Functions
    ***************************************************************************/

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata liquidityManagement
    ) public override onlyVault returns (bool success) {
        (IGyroECLPPool.EclpParams memory eclpParams, ) = IGyroECLPPool(pool).getECLPParams();

        // The surge hook only works for pools with a rotation angle between 30 and 60 degrees. Outside of this range,
        // the computation of the peak price cannot be approximated by sine/cosine.
        if (eclpParams.s < 50e16 || eclpParams.c < 50e16) {
            revert InvalidRotationAngleForSurgeHook();
        }

        success = super.onRegister(factory, pool, tokenConfig, liquidityManagement);

        emit ECLPSurgeHookRegistered(pool, factory);
    }

    /***************************************************************************
                                  Private Functions
    ***************************************************************************/

    function _isSurgingSwap(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage,
        SurgeFeeData memory surgeFeeData
    ) internal view override returns (bool isSurging, uint256 newTotalImbalance) {
        // If the max surge fee percentage is less than the static fee percentage, return false.
        // No matter where the imbalance is, surge is never lower than the static fee.
        if (surgeFeeData.maxSurgeFeePercentage < staticSwapFeePercentage) {
            return (false, 0);
        }

        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
        ) = IGyroECLPPool(pool).getECLPParams();

        (uint256 amountCalculatedScaled18, int256 a, int256 b) = _computeSwap(params, eclpParams, derivedECLPParams);

        uint256[] memory newBalances = new uint256[](params.balancesScaled18.length);
        ScalingHelpers.copyToArray(params.balancesScaled18, newBalances);

        if (params.kind == SwapKind.EXACT_IN) {
            newBalances[params.indexIn] += params.amountGivenScaled18;
            newBalances[params.indexOut] -= amountCalculatedScaled18;
        } else {
            newBalances[params.indexIn] += amountCalculatedScaled18;
            newBalances[params.indexOut] -= params.amountGivenScaled18;
        }

        uint256 oldTotalImbalance = _computeImbalance(params.balancesScaled18, eclpParams, a, b);

        newTotalImbalance = _computeImbalance(newBalances, eclpParams, a, b);
        isSurging = _isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance);
    }

    function _isSurgingUnbalancedLiquidity(
        address pool,
        uint256[] memory oldBalancesScaled18,
        uint256[] memory balancesScaled18
    ) internal view override returns (bool isSurging) {
        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];

        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
        ) = IGyroECLPPool(pool).getECLPParams();

        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(
            oldBalancesScaled18,
            eclpParams,
            derivedECLPParams
        );
        oldTotalImbalance = _computeImbalance(oldBalancesScaled18, eclpParams, a, b);

        // Since the invariant is not the same after the liquidity change, we need to recompute the offset.
        (a, b) = GyroECLPMath.computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
        newTotalImbalance = _computeImbalance(balancesScaled18, eclpParams, a, b);

        isSurging = _isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance);
    }

    /**
     * @dev This function is a copy of the `onSwap` function in the E-CLP pool. However, it exposes the a and b
     * parameters, which are needed to compute the imbalance, therefore saving gas.
     */
    function _computeSwap(
        PoolSwapParams memory request,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
    ) internal pure returns (uint256 amountCalculated, int256 a, int256 b) {
        // The Vault already checks that index in != index out.
        bool tokenInIsToken0 = request.indexIn == 0;

        IGyroECLPPool.Vector2 memory invariant;

        (int256 currentInvariant, int256 invErr) = GyroECLPMath.calculateInvariantWithError(
            request.balancesScaled18,
            eclpParams,
            derivedECLPParams
        );
        // invariant = overestimate in x-component, underestimate in y-component
        // No overflow in `+` due to constraints to the different values enforced in GyroECLPMath.
        invariant = IGyroECLPPool.Vector2(currentInvariant + 2 * invErr, currentInvariant);

        if (request.kind == SwapKind.EXACT_IN) {
            (amountCalculated, a, b) = GyroECLPMath.calcOutGivenIn(
                request.balancesScaled18,
                request.amountGivenScaled18,
                tokenInIsToken0,
                eclpParams,
                derivedECLPParams,
                invariant
            );
        } else {
            (amountCalculated, a, b) = GyroECLPMath.calcInGivenOut(
                request.balancesScaled18,
                request.amountGivenScaled18,
                tokenInIsToken0,
                eclpParams,
                derivedECLPParams,
                invariant
            );
        }
    }

    function _computeImbalance(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        int256 a,
        int256 b
    ) internal pure returns (uint256 imbalance) {
        // On E-CLPs, the imbalance is a number from 0 to 1 that represents how far the current price is from the
        // peak liquidity price (the price in which the liquidity of the pool is maximized).
        // To reach this number, first we compute the peak price, which is sine/cosine (the tangent of the E-CLP
        // rotation angle). Then, we compute the current price. We check if the current price is above or below the
        // peak price:
        // - If the current price is equal to the peak price, imbalance = 0 (the pool is perfectly balanced)
        // - If the current price is below peak, imbalance = (peakPrice - currentPrice) / (peakPrice - alpha)
        // - If the current price is above peak, imbalance = (currentPrice - peakPrice) / (beta - peakPrice)

        // Compute current price
        uint256 currentPrice = GyroECLPMath.computePrice(balancesScaled18, eclpParams, a, b);

        // Compute peak price, defined by `sine / cosine`, which is the price where the pool has the largest liquidity.
        uint256 peakPrice = eclpParams.s.divDownMag(eclpParams.c).toUint256();
        // The price cannot be outside of pool range.
        peakPrice = GyroECLPMath.clampPriceToPoolRange(peakPrice, eclpParams);

        if (currentPrice == peakPrice) {
            // If the currentPrice equals the peak price, the pool is perfectly balanced.
            return 0;
        } else if (currentPrice < peakPrice) {
            return (peakPrice - currentPrice).divDown(peakPrice - eclpParams.alpha.toUint256());
        } else {
            return (currentPrice - peakPrice).divDown(eclpParams.beta.toUint256() - peakPrice);
        }
    }
}
