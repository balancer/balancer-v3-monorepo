// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IECLPSurgeHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IECLPSurgeHook.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    LiquidityManagement,
    TokenConfig,
    TokenInfo,
    PoolSwapParams,
    HookFlags,
    RemoveLiquidityKind,
    SwapKind,
    Rounding
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { SignedFixedPoint } from "@balancer-labs/v3-pool-gyro/contracts/lib/SignedFixedPoint.sol";
import { GyroECLPMath } from "@balancer-labs/v3-pool-gyro/contracts/lib/GyroECLPMath.sol";
import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a "surge" fee on trades that unbalance the pool beyond the threshold.
 */
contract ECLPSurgeHook is IECLPSurgeHook, BaseHooks, VaultGuard, SingletonAuthentication, Version {
    using SignedFixedPoint for int256;
    using FixedPoint for uint256;
    using SafeCast for *;

    // Percentages are 18-decimal FP values, which fit in 64 bits (sized ensure a single slot).
    struct SurgeFeeData {
        uint64 thresholdPercentage;
        uint64 maxSurgeFeePercentage;
    }

    // The default threshold, above which surging will occur.
    uint256 private immutable _defaultMaxSurgeFeePercentage;

    // The default threshold, above which surging will occur.
    uint256 private immutable _defaultSurgeThresholdPercentage;

    // Store the current threshold and max fee for each pool.
    mapping(address pool => SurgeFeeData data) internal _surgeFeePoolData;

    modifier withValidPercentage(uint256 percentageValue) {
        _ensureValidPercentage(percentageValue);
        _;
    }

    constructor(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) SingletonAuthentication(vault) VaultGuard(vault) Version(version) {
        _ensureValidPercentage(defaultMaxSurgeFeePercentage);
        _ensureValidPercentage(defaultSurgeThresholdPercentage);

        _defaultMaxSurgeFeePercentage = defaultMaxSurgeFeePercentage;
        _defaultSurgeThresholdPercentage = defaultSurgeThresholdPercentage;
    }

    /***************************************************************************
                                IHooks Functions
    ***************************************************************************/

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        // Initially set the max pool surge percentage to the default (can be changed by the pool swapFeeManager
        // in the future).
        _setMaxSurgeFeePercentage(pool, _defaultMaxSurgeFeePercentage);

        // Initially set the pool threshold to the default (can be changed by the pool swapFeeManager in the future).
        _setSurgeThresholdPercentage(pool, _defaultSurgeThresholdPercentage);

        emit ECLPSurgeHookRegistered(pool, factory);

        return true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        return (true, _computeSwapSurgeFeePercentage(params, pool, staticSwapFeePercentage));
    }

    /// @inheritdoc IHooks
    function onAfterAddLiquidity(
        address,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory balancesScaled18,
        bytes memory
    ) public view override returns (bool success, uint256[] memory hookAdjustedAmountsInRaw) {
        // Proportional add is always fine.
        if (kind == AddLiquidityKind.PROPORTIONAL) {
            return (true, amountsInRaw);
        }

        // Rebuild old balances before adding liquidity.
        uint256[] memory oldBalancesScaled18 = new uint256[](balancesScaled18.length);
        for (uint256 i = 0; i < balancesScaled18.length; ++i) {
            oldBalancesScaled18[i] = balancesScaled18[i] - amountsInScaled18[i];
        }

        bool isSurging = _isSurgingUnbalancedLiquidity(pool, oldBalancesScaled18, balancesScaled18);

        // If we're not surging, it's fine to proceed; otherwise halt execution by returning false.
        return (isSurging == false, amountsInRaw);
    }

    /// @inheritdoc IHooks
    function onAfterRemoveLiquidity(
        address,
        address pool,
        RemoveLiquidityKind kind,
        uint256,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256[] memory balancesScaled18,
        bytes memory
    ) public view override returns (bool success, uint256[] memory hookAdjustedAmountsOutRaw) {
        // Proportional remove is always fine.
        if (kind == RemoveLiquidityKind.PROPORTIONAL) {
            return (true, amountsOutRaw);
        }

        // Rebuild old balances before removing liquidity.
        uint256[] memory oldBalancesScaled18 = new uint256[](balancesScaled18.length);
        for (uint256 i = 0; i < balancesScaled18.length; ++i) {
            oldBalancesScaled18[i] = balancesScaled18[i] + amountsOutScaled18[i];
        }

        bool isSurging = _isSurgingUnbalancedLiquidity(pool, oldBalancesScaled18, balancesScaled18);

        // If we're not surging, it's fine to proceed; otherwise halt execution by returning false.
        return (isSurging == false, amountsOutRaw);
    }

    /***************************************************************************
                          ECLP Surge Hook Functions
    ***************************************************************************/

    /// @inheritdoc IECLPSurgeHook
    function getDefaultMaxSurgeFeePercentage() external view returns (uint256) {
        return _defaultMaxSurgeFeePercentage;
    }

    /// @inheritdoc IECLPSurgeHook
    function getDefaultSurgeThresholdPercentage() external view returns (uint256) {
        return _defaultSurgeThresholdPercentage;
    }

    /// @inheritdoc IECLPSurgeHook
    function getMaxSurgeFeePercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].maxSurgeFeePercentage;
    }

    /// @inheritdoc IECLPSurgeHook
    function getSurgeThresholdPercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].thresholdPercentage;
    }

    /// @inheritdoc IECLPSurgeHook
    function setMaxSurgeFeePercentage(
        address pool,
        uint256 newMaxSurgeSurgeFeePercentage
    ) external withValidPercentage(newMaxSurgeSurgeFeePercentage) onlySwapFeeManagerOrGovernance(pool) {
        _setMaxSurgeFeePercentage(pool, newMaxSurgeSurgeFeePercentage);
    }

    /// @inheritdoc IECLPSurgeHook
    function setSurgeThresholdPercentage(
        address pool,
        uint256 newSurgeThresholdPercentage
    ) external withValidPercentage(newSurgeThresholdPercentage) onlySwapFeeManagerOrGovernance(pool) {
        _setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    /// @inheritdoc IECLPSurgeHook
    function computeSwapSurgeFeePercentage(PoolSwapParams calldata params, address pool) public view returns (uint256) {
        uint256 staticSwapFeePercentage = _vault.getStaticSwapFeePercentage(pool);
        return _computeSwapSurgeFeePercentage(params, pool, staticSwapFeePercentage);
    }

    /***************************************************************************
                                  Private Functions
    ***************************************************************************/

    function _computeSwapSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) private view returns (uint256 surgeFeePercentage) {
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

        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];

        // If the max surge fee percentage is less than the static fee percentage, return the static fee percentage.
        // No matter where the imbalance is, the fee can never be smaller than the static fee.
        if (surgeFeeData.maxSurgeFeePercentage < staticSwapFeePercentage) {
            return staticSwapFeePercentage;
        }

        uint256 oldTotalImbalance = _computeImbalance(params.balancesScaled18, eclpParams, a, b);
        uint256 newTotalImbalance = _computeImbalance(newBalances, eclpParams, a, b);

        bool isSurging = _isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance);

        // surgeFee = staticFee + (maxFee - staticFee) * (pctImbalance - pctThreshold) / (1 - pctThreshold).
        //
        // As you can see from the formula, if it’s unbalanced exactly at the threshold, the last term is 0,
        // and the fee is just: static + 0 = static fee.
        // As the unbalanced proportion term approaches 1, the fee surge approaches: static + max - static ~= max fee.
        // This formula linearly increases the fee from 0 at the threshold up to the maximum fee.
        // At 35%, the fee would be 1% + (0.95 - 0.01) * ((0.35 - 0.3)/(0.95-0.3)) = 1% + 0.94 * 0.0769 ~ 8.2%.
        // At 50% unbalanced, the fee would be 44%. At 99% unbalanced, the fee would be ~94%, very close to the maximum.
        if (isSurging) {
            surgeFeePercentage =
                staticSwapFeePercentage +
                (surgeFeeData.maxSurgeFeePercentage - staticSwapFeePercentage).mulDown(
                    (newTotalImbalance - surgeFeeData.thresholdPercentage).divDown(
                        uint256(surgeFeeData.thresholdPercentage).complement()
                    )
                );
        } else {
            surgeFeePercentage = staticSwapFeePercentage;
        }
    }

    function _isSurgingUnbalancedLiquidity(
        address pool,
        uint256[] memory oldBalancesScaled18,
        uint256[] memory balancesScaled18
    ) internal view returns (bool isSurging) {
        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];

        (
            IGyroECLPPool.EclpParams memory eclpParams,
            IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
        ) = IGyroECLPPool(pool).getECLPParams();

        uint256 oldTotalImbalance;
        uint256 newTotalImbalance;

        {
            (int256 a, int256 b) = _computeOffsetFromBalances(oldBalancesScaled18, eclpParams, derivedECLPParams);
            oldTotalImbalance = _computeImbalance(oldBalancesScaled18, eclpParams, a, b);
        }

        {
            // Since the invariant is not the same after the liquidity change, we need to recompute the offset.
            (int256 a, int256 b) = _computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
            newTotalImbalance = _computeImbalance(balancesScaled18, eclpParams, a, b);
        }

        isSurging = _isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance);
    }

    function _isSurging(
        uint64 thresholdPercentage,
        uint256 oldTotalImbalance,
        uint256 newTotalImbalance
    ) internal pure returns (bool isSurging) {
        // If we are balanced, or the balance has improved, do not surge: simply return the regular fee percentage.
        if (newTotalImbalance == 0) {
            return false;
        }

        // Surging if imbalance grows and we're currently above the threshold.
        return (newTotalImbalance > oldTotalImbalance && newTotalImbalance > thresholdPercentage);
    }

    /// @dev Assumes the percentage value and sender have been externally validated.
    function _setMaxSurgeFeePercentage(address pool, uint256 newMaxSurgeFeePercentage) private {
        // Still use SafeCast out of an abundance of caution.
        _surgeFeePoolData[pool].maxSurgeFeePercentage = newMaxSurgeFeePercentage.toUint64();

        emit MaxSurgeFeePercentageChanged(pool, newMaxSurgeFeePercentage);
    }

    /// @dev Assumes the percentage value and sender have been externally validated.
    function _setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) private {
        // Still use SafeCast out of an abundance of caution.
        _surgeFeePoolData[pool].thresholdPercentage = newSurgeThresholdPercentage.toUint64();

        emit ThresholdSurgePercentageChanged(pool, newSurgeThresholdPercentage);
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

        {
            (int256 currentInvariant, int256 invErr) = GyroECLPMath.calculateInvariantWithError(
                request.balancesScaled18,
                eclpParams,
                derivedECLPParams
            );
            // invariant = overestimate in x-component, underestimate in y-component
            // No overflow in `+` due to constraints to the different values enforced in GyroECLPMath.
            invariant = IGyroECLPPool.Vector2(currentInvariant + 2 * invErr, currentInvariant);
        }

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
        uint256 currentPrice = _computePrice(balancesScaled18, eclpParams, a, b);

        // Compute peak price, defined by `sine / cosine`, which is the price where the pool has the largest liquidity.
        uint256 peakPrice = eclpParams.s.divDownMag(eclpParams.c).toUint256();
        // The peak price may be outside the [alpha, beta] interval, so we clamp it to the interval.
        if (peakPrice < eclpParams.alpha.toUint256()) {
            peakPrice = eclpParams.alpha.toUint256();
        } else if (peakPrice > eclpParams.beta.toUint256()) {
            peakPrice = eclpParams.beta.toUint256();
        }

        if (currentPrice == peakPrice) {
            // If currentPrice equals to peak price, the pool is perfectly balanced.
            return 0;
        } else if (currentPrice < peakPrice) {
            return (peakPrice - currentPrice).divDown(peakPrice - eclpParams.alpha.toUint256());
        } else {
            return (currentPrice - peakPrice).divDown(eclpParams.beta.toUint256() - peakPrice);
        }
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
        //     --   --    --                     --   --     --
        //     | x'' |    |  c/lambda  -s/lambda  | * | x - a |
        //     | y'' | =  |     s          c      |   | y - b |
        //     --   --    --                     --   --     --
        //
        // With x'' and y'', we can compute the price as:
        //
        //                          --              --   --   --
        //             [xll, yll] o |  c/lambda   s  | * |  1  |
        //                          | -s/lambda   c  |   |  0  |
        //                          --              --   --   --
        //    price =  -------------------------------------------
        //                          --              --   --   --
        //             [xll, yll] o |  c/lambda   s  | * |  0  |
        //                          | -s/lambda   c  |   |  1  |
        //                          --              --   --   --

        // Balances in the rotated ellipse centered at (0,0)
        int256 xl = int256(balancesScaled18[0]) - a;
        int256 yl = int256(balancesScaled18[1]) - b;

        // Balances in the circle centered at (0,0)
        int256 xll = xl.mulDownMag(eclpParams.c).divDownMag(eclpParams.lambda) -
            yl.mulDownMag(eclpParams.s).divDownMag(eclpParams.lambda);
        int256 yll = xl.mulDownMag(eclpParams.s) + yl.mulDownMag(eclpParams.c);

        // Scalar product of [xll, yll] by A*[1,0] => e_x (unity vector in the x direction).
        int256 numerator = xll.mulDownMag(eclpParams.c).divDownMag(eclpParams.lambda) + yll.mulDownMag(eclpParams.s);
        // Scalar product of [xll, yll] by A*[0,1] => e_y (unity vector in the y direction).
        int256 denominator = yll.mulDownMag(eclpParams.c) - xll.mulDownMag(eclpParams.s).divDownMag(eclpParams.lambda);

        price = numerator.divDownMag(denominator).toUint256();

        // The price cannot be outside of pool range.
        if (price < eclpParams.alpha.toUint256()) {
            price = eclpParams.alpha.toUint256();
        } else if (price > eclpParams.beta.toUint256()) {
            price = eclpParams.beta.toUint256();
        }

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
            // No overflow in `+` due to constraints to the different values enforced in GyroECLPMath.
            invariant = IGyroECLPPool.Vector2(currentInvariant + 2 * invErr, currentInvariant);
        }

        a = GyroECLPMath.virtualOffset0(eclpParams, derivedECLPParams, invariant);
        b = GyroECLPMath.virtualOffset1(eclpParams, derivedECLPParams, invariant);
    }

    function _ensureValidPercentage(uint256 percentage) private pure {
        if (percentage > FixedPoint.ONE) {
            revert InvalidPercentage();
        }
    }
}
