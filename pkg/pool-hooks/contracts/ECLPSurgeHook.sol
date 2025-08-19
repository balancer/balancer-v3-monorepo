// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IECLPSurgeHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IECLPSurgeHook.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { SignedFixedPoint } from "@balancer-labs/v3-pool-gyro/contracts/lib/SignedFixedPoint.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { GyroECLPMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroECLPMath.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import { SurgeHookCommon } from "./SurgeHookCommon.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a "surge" fee on trades that unbalance the pool beyond the threshold.
 */
contract ECLPSurgeHook is IECLPSurgeHook, SurgeHookCommon {
    using SignedFixedPoint for int256;
    using FixedPoint for uint256;
    using SafeCast for *;

    // Cannot use FixedPoint.ONE because the constant is a uint128.
    uint128 internal constant _DEFAULT_IMBALANCE_SLOPE = 1e18;

    // Store the current below and above peak slopes for each pool.
    mapping(address pool => ImbalanceSlopeData data) internal _imbalanceSlopePoolData;

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
        success = super.onRegister(factory, pool, tokenConfig, liquidityManagement);

        _setImbalanceSlopeBelowPeak(pool, _DEFAULT_IMBALANCE_SLOPE);
        _setImbalanceSlopeAbovePeak(pool, _DEFAULT_IMBALANCE_SLOPE);

        emit ECLPSurgeHookRegistered(pool, factory);
    }

    /***************************************************************************
                          E-CLP Hook Getters and Setters
    ***************************************************************************/

    /// @inheritdoc IECLPSurgeHook
    function getImbalanceSlopeBelowPeak(address pool) external view returns (uint128) {
        return _imbalanceSlopePoolData[pool].imbalanceSlopeBelowPeak;
    }

    /// @inheritdoc IECLPSurgeHook
    function getImbalanceSlopeAbovePeak(address pool) external view returns (uint128) {
        return _imbalanceSlopePoolData[pool].imbalanceSlopeAbovePeak;
    }

    /// @inheritdoc IECLPSurgeHook
    function setImbalanceSlopeBelowPeak(
        address pool,
        uint128 newImbalanceSlopeBelowPeak
    ) external onlySwapFeeManagerOrGovernance(pool) {
        _setImbalanceSlopeBelowPeak(pool, newImbalanceSlopeBelowPeak);
    }

    /// @inheritdoc IECLPSurgeHook
    function setImbalanceSlopeAbovePeak(
        address pool,
        uint128 newImbalanceSlopeAbovePeak
    ) external onlySwapFeeManagerOrGovernance(pool) {
        _setImbalanceSlopeAbovePeak(pool, newImbalanceSlopeAbovePeak);
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

        ImbalanceSlopeData memory imbalanceSlopeData = _imbalanceSlopePoolData[pool];

        uint256 oldTotalImbalance = _computeImbalance(params.balancesScaled18, eclpParams, a, b, imbalanceSlopeData);

        newTotalImbalance = _computeImbalance(newBalances, eclpParams, a, b, imbalanceSlopeData);
        isSurging = _isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance);
    }

    function _isSurgingUnbalancedLiquidity(
        address pool,
        uint256[] memory oldBalancesScaled18,
        uint256[] memory balancesScaled18
    ) internal view override returns (bool isSurging) {
        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];
        ImbalanceSlopeData memory imbalanceSlopeData = _imbalanceSlopePoolData[pool];

        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
        ) = IGyroECLPPool(pool).getECLPParams();

        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        (int256 a, int256 b) = _computeOffsetFromBalances(oldBalancesScaled18, eclpParams, derivedECLPParams);
        oldTotalImbalance = _computeImbalance(oldBalancesScaled18, eclpParams, a, b, imbalanceSlopeData);

        // Since the invariant is not the same after the liquidity change, we need to recompute the offset.
        (a, b) = _computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
        newTotalImbalance = _computeImbalance(balancesScaled18, eclpParams, a, b, imbalanceSlopeData);

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
        int256 b,
        ImbalanceSlopeData memory imbalanceSlopeData
    ) internal pure returns (uint256 imbalance) {
        // On E-CLPs, the imbalance is a number from 0 to 1 that represents how far the current price is from the
        // peak liquidity price (the price in which the liquidity of the pool is maximized).
        // To reach this number, first we compute the peak price, which is sine/cosine (the tangent of the E-CLP
        // rotation angle). Then, we compute the current price. We check if the current price is above or below the
        // peak price:
        // - currentPrice == peakPrice, imbalance = 0 (the pool is perfectly balanced)
        // - currentPrice < peakPrice, imbalance = belowPeakSlope * (peakPrice - currentPrice) / (peakPrice - alpha)
        // - currentPrice > peakPrice, imbalance = abovePeakSlope * (currentPrice - peakPrice) / (beta - peakPrice)

        // Compute current price
        uint256 currentPrice = _computePrice(balancesScaled18, eclpParams, a, b);

        // Compute peak price, defined by `sine / cosine`, which is the price where the pool has the largest liquidity.
        uint256 peakPrice = eclpParams.s.divDownMag(eclpParams.c).toUint256();
        // The price cannot be outside of pool range.
        peakPrice = _clampPriceToPoolRange(peakPrice, eclpParams);

        if (currentPrice == peakPrice) {
            // If the currentPrice equals the peak price, the pool is perfectly balanced.
            return 0;
        } else if (currentPrice < peakPrice) {
            imbalance =
                ((peakPrice - currentPrice) * imbalanceSlopeData.imbalanceSlopeBelowPeak) /
                (peakPrice - eclpParams.alpha.toUint256());
        } else {
            imbalance =
                ((currentPrice - peakPrice) * imbalanceSlopeData.imbalanceSlopeAbovePeak) /
                (eclpParams.beta.toUint256() - peakPrice);
        }

        if (imbalance > FixedPoint.ONE) {
            return FixedPoint.ONE;
        }

        return imbalance;
    }

    function _computePrice(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        int256 a,
        int256 b
    ) internal pure returns (uint256 price) {
        // To compute the price, first we need to transform the real balances into balances of a circle centered at
        // (0,0).
        //
        // The transformation is:
        //
        //     --   --    --           --   --     --
        //     | x'' |    |  c/λ  -s/λ  | * | x - a |
        //     | y'' | =  |   s     c   |   | y - b |
        //     --   --    --           --   --     --
        //
        // With x'' and y'', we can compute the price as:
        //
        //                          --            --   --   --
        //             [xll, yll] o |  c/λ   -s/λ  | * |  1  |
        //                          |   s      c   |   |  0  |
        //                          --            --   --   --
        //    price =  -------------------------------------------
        //                          --            --   --   --
        //             [xll, yll] o |  c/λ   -s/λ  | * |  0  |
        //                          |   s      c   |   |  1  |
        //                          --            --   --   --

        // Balances in the rotated ellipse centered at (0,0)
        int256 xl = int256(balancesScaled18[0]) - a;
        int256 yl = int256(balancesScaled18[1]) - b;

        // Balances in the circle centered at (0,0)
        int256 xll = (xl * eclpParams.c - yl * eclpParams.s) / eclpParams.lambda;
        int256 yll = (xl * eclpParams.s + yl * eclpParams.c) / 1e18;

        // Scalar product of [xll, yll] by A*[1,0] => e_x (unity vector in the x direction).
        int256 numerator = yll.mulDownMag(eclpParams.s) + ((xll * eclpParams.c) / eclpParams.lambda);
        // Scalar product of [xll, yll] by A*[0,1] => e_y (unity vector in the y direction).
        int256 denominator = yll.mulDownMag(eclpParams.c) - ((xll * eclpParams.s) / eclpParams.lambda);

        price = numerator.divDownMag(denominator).toUint256();
        // The price cannot be outside of pool range.
        price = _clampPriceToPoolRange(price, eclpParams);

        return price;
    }

    function _computeOffsetFromBalances(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
    ) internal pure returns (int256 a, int256 b) {
        IGyroECLPPool.Vector2 memory invariant;

        {
            (int256 currentInvariant, int256 invErr) = GyroECLPMath.calculateInvariantWithError(
                balancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            // invariant = overestimate in x-component, underestimate in y-component
            // No overflow in `+` due to constraints to the different values enforced in GyroECLPMath (the sum of the
            // balances of the tokens cannot exceed 1e34, so the invariant + err value is bounded by 3e37).
            invariant = IGyroECLPPool.Vector2(currentInvariant + 2 * invErr, currentInvariant);
        }

        a = GyroECLPMath.virtualOffset0(eclpParams, derivedECLPParams, invariant);
        b = GyroECLPMath.virtualOffset1(eclpParams, derivedECLPParams, invariant);
    }

    function _setImbalanceSlopeBelowPeak(address pool, uint128 newImbalanceSlopeBelowPeak) internal {
        _imbalanceSlopePoolData[pool].imbalanceSlopeBelowPeak = newImbalanceSlopeBelowPeak;
        emit ImbalanceSlopeBelowPeakChanged(pool, newImbalanceSlopeBelowPeak);
    }

    function _setImbalanceSlopeAbovePeak(address pool, uint128 newImbalanceSlopeAbovePeak) internal {
        _imbalanceSlopePoolData[pool].imbalanceSlopeAbovePeak = newImbalanceSlopeAbovePeak;
        emit ImbalanceSlopeAbovePeakChanged(pool, newImbalanceSlopeAbovePeak);
    }

    /**
     * @notice Clamps the price to the pool range.
     * @dev The pool price cannot be lower than alpha or higher than beta. So, we clamp it to the interval.
     * @param price The price to clamp
     * @param eclpParams The E-CLP parameters
     * @return The clamped price
     */
    function _clampPriceToPoolRange(
        uint256 price,
        IGyroECLPPool.EclpParams memory eclpParams
    ) internal pure returns (uint256) {
        if (price < eclpParams.alpha.toUint256()) {
            return eclpParams.alpha.toUint256();
        } else if (price > eclpParams.beta.toUint256()) {
            return eclpParams.beta.toUint256();
        }
        return price;
    }
}
