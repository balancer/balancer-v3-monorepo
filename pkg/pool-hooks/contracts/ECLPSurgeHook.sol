// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IECLPSurgeHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IECLPSurgeHook.sol";
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
contract ECLPSurgeHook is IECLPSurgeHook, SurgeHookCommon {
    using SignedFixedPoint for int256;
    using FixedPoint for uint256;
    using SafeCast for *;

    struct ImbalanceSlopeData {
        uint128 imbalanceSlopeBelowPeak;
        uint128 imbalanceSlopeAbovePeak;
    }

    uint128 internal constant _DEFAULT_IMBALANCE_SLOPE = uint128(FixedPoint.ONE);

    // These limits are arbitrary. However, slopes smaller than 0.01 would mean a static fee charged for almost all
    // swaps, while slopes larger than 100 would mean the max surge fee charged for almost all swaps. Therefore, values
    // outside of these limits are unlikely to be useful.
    uint128 public constant MIN_IMBALANCE_SLOPE = 0.01e18;
    uint128 public constant MAX_IMBALANCE_SLOPE = 100e18;

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
        (IGyroECLPPool.EclpParams memory eclpParams, ) = IGyroECLPPool(pool).getECLPParams();

        // The surge hook only works for pools with a rotation angle between 30 and 60 degrees. Outside of this range,
        // the computation of the peak price cannot be approximated by sine/cosine. Notice that sin(30deg) = 0.5, and
        // cos(60deg) = 0.5. Therefore, we can use 0.5 as the threshold for the sine and cosine, given that in the
        // interval [30deg, 60deg], both sine and cosine are greater than 0.5.
        if (eclpParams.s < 50e16 || eclpParams.c < 50e16) {
            revert InvalidRotationAngle();
        }

        success = super.onRegister(factory, pool, tokenConfig, liquidityManagement);

        _setImbalanceSlopeBelowPeak(pool, _DEFAULT_IMBALANCE_SLOPE);
        _setImbalanceSlopeAbovePeak(pool, _DEFAULT_IMBALANCE_SLOPE);

        emit ECLPSurgeHookRegistered(pool, factory);
    }

    /***************************************************************************
                          E-CLP Hook Getters and Setters
    ***************************************************************************/

    /// @inheritdoc IECLPSurgeHook
    function getImbalanceSlopes(address pool) external view returns (uint256, uint256) {
        ImbalanceSlopeData memory imbalanceSlopeData = _imbalanceSlopePoolData[pool];
        return (imbalanceSlopeData.imbalanceSlopeBelowPeak, imbalanceSlopeData.imbalanceSlopeAbovePeak);
    }

    /// @inheritdoc IECLPSurgeHook
    function setImbalanceSlopeBelowPeak(
        address pool,
        uint256 newImbalanceSlopeBelowPeak
    ) external onlySwapFeeManagerOrGovernance(pool) {
        _setImbalanceSlopeBelowPeak(pool, newImbalanceSlopeBelowPeak);
    }

    /// @inheritdoc IECLPSurgeHook
    function setImbalanceSlopeAbovePeak(
        address pool,
        uint256 newImbalanceSlopeAbovePeak
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

        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(
            oldBalancesScaled18,
            eclpParams,
            derivedECLPParams
        );
        oldTotalImbalance = _computeImbalance(oldBalancesScaled18, eclpParams, a, b, imbalanceSlopeData);

        // Since the invariant is not the same after the liquidity change, we need to recompute the offset.
        (a, b) = GyroECLPMath.computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
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
        uint256 currentPrice = GyroECLPMath.computePrice(balancesScaled18, eclpParams, a, b);

        // Compute peak price, defined by `sine / cosine`, which is the price where the pool has the largest liquidity.
        uint256 peakPrice = eclpParams.s.divDownMag(eclpParams.c).toUint256();
        // The price cannot be outside of pool range.
        peakPrice = GyroECLPMath.clampPriceToPoolRange(peakPrice, eclpParams);

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

        return imbalance > FixedPoint.ONE ? FixedPoint.ONE : imbalance;
    }

    function _setImbalanceSlopeBelowPeak(address pool, uint256 newImbalanceSlopeBelowPeak) internal {
        _ensureValidImbalanceSlope(newImbalanceSlopeBelowPeak);

        // Since the slope is < MAX_IMBALANCE_SLOPE, which is a uint128 number, we can cast it to uint128.
        uint128 newImbalanceSlopeBelowPeak128 = newImbalanceSlopeBelowPeak.toUint128();

        _imbalanceSlopePoolData[pool].imbalanceSlopeBelowPeak = newImbalanceSlopeBelowPeak128;
        emit ImbalanceSlopeBelowPeakChanged(pool, newImbalanceSlopeBelowPeak128);
    }

    function _setImbalanceSlopeAbovePeak(address pool, uint256 newImbalanceSlopeAbovePeak) internal {
        _ensureValidImbalanceSlope(newImbalanceSlopeAbovePeak);

        // Since the slope is < MAX_IMBALANCE_SLOPE, which is a uint128 number, we can cast it to uint128.
        uint128 newImbalanceSlopeAbovePeak128 = newImbalanceSlopeAbovePeak.toUint128();

        _imbalanceSlopePoolData[pool].imbalanceSlopeAbovePeak = newImbalanceSlopeAbovePeak128;
        emit ImbalanceSlopeAbovePeakChanged(pool, newImbalanceSlopeAbovePeak128);
    }

    function _ensureValidImbalanceSlope(uint256 newImbalanceSlope) internal pure {
        if (newImbalanceSlope > MAX_IMBALANCE_SLOPE || newImbalanceSlope < MIN_IMBALANCE_SLOPE) {
            revert InvalidImbalanceSlope();
        }
    }
}
