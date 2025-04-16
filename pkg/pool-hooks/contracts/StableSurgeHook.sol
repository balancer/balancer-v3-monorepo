// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IStableSurgeHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IStableSurgeHook.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    LiquidityManagement,
    TokenConfig,
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

import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { StableSurgeMedianMath } from "./utils/StableSurgeMedianMath.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a "surge" fee on trades that unbalance the pool beyond the threshold.
 */
contract StableSurgeHook is IStableSurgeHook, BaseHooks, VaultGuard, SingletonAuthentication, Version {
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

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
    }

    /// @inheritdoc IStableSurgeHook
    function getDefaultMaxSurgeFeePercentage() external view returns (uint256) {
        return _defaultMaxSurgeFeePercentage;
    }

    /// @inheritdoc IStableSurgeHook
    function getDefaultSurgeThresholdPercentage() external view returns (uint256) {
        return _defaultSurgeThresholdPercentage;
    }

    /// @inheritdoc IStableSurgeHook
    function getMaxSurgeFeePercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].maxSurgeFeePercentage;
    }

    /// @inheritdoc IStableSurgeHook
    function getSurgeThresholdPercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].thresholdPercentage;
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

        emit StableSurgeHookRegistered(pool, factory);

        return true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        return (true, getSurgeFeePercentage(params, pool, staticSwapFeePercentage));
    }

    function getSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view returns (uint256) {
        uint256 amountCalculatedScaled18 = StablePool(pool).onSwap(params);

        uint256[] memory newBalances = new uint256[](params.balancesScaled18.length);
        ScalingHelpers.copyToArray(params.balancesScaled18, newBalances);

        if (params.kind == SwapKind.EXACT_IN) {
            newBalances[params.indexIn] += params.amountGivenScaled18;
            newBalances[params.indexOut] -= amountCalculatedScaled18;
        } else {
            newBalances[params.indexIn] += amountCalculatedScaled18;
            newBalances[params.indexOut] -= params.amountGivenScaled18;
        }

        return _getSurgeFeePercentage(params, pool, staticSwapFeePercentage, newBalances);
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

        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];
        uint256 newTotalImbalance = StableSurgeMedianMath.calculateImbalance(balancesScaled18);

        bool isSurging = _isSurging(surgeFeeData, oldBalancesScaled18, newTotalImbalance);

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

        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];
        uint256 newTotalImbalance = StableSurgeMedianMath.calculateImbalance(balancesScaled18);

        bool isSurging = _isSurging(surgeFeeData, oldBalancesScaled18, newTotalImbalance);

        // If we're not surging, it's fine to proceed; otherwise halt execution by returning false.
        return (isSurging == false, amountsOutRaw);
    }

    /// @inheritdoc IStableSurgeHook
    function setMaxSurgeFeePercentage(
        address pool,
        uint256 newMaxSurgeSurgeFeePercentage
    ) external withValidPercentage(newMaxSurgeSurgeFeePercentage) onlySwapFeeManagerOrGovernance(pool) {
        _setMaxSurgeFeePercentage(pool, newMaxSurgeSurgeFeePercentage);
    }

    /// @inheritdoc IStableSurgeHook
    function setSurgeThresholdPercentage(
        address pool,
        uint256 newSurgeThresholdPercentage
    ) external withValidPercentage(newSurgeThresholdPercentage) onlySwapFeeManagerOrGovernance(pool) {
        _setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    /**
     * @notice Calculate the surge fee percentage. If below threshold, return the standard static swap fee percentage.
     * @dev It is public to allow it to be called off-chain.
     * @param params Input parameters for the swap (balances needed)
     * @param pool The pool we are computing the fee for
     * @param staticFeePercentage The static fee percentage for the pool (default if there is no surge)
     */
    function _getSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticFeePercentage,
        uint256[] memory newBalances
    ) internal view returns (uint256 surgeFeePercentage) {
        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];

        // If the max surge fee percentage is less than the static fee percentage, return the static fee percentage.
        // No matter where the imbalance is, the fee can never be smaller than the static fee.
        if (surgeFeeData.maxSurgeFeePercentage < staticFeePercentage) {
            return staticFeePercentage;
        }

        uint256 newTotalImbalance = StableSurgeMedianMath.calculateImbalance(newBalances);

        bool isSurging = _isSurging(surgeFeeData, params.balancesScaled18, newTotalImbalance);

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
                staticFeePercentage +
                (surgeFeeData.maxSurgeFeePercentage - staticFeePercentage).mulDown(
                    (newTotalImbalance - surgeFeeData.thresholdPercentage).divDown(
                        uint256(surgeFeeData.thresholdPercentage).complement()
                    )
                );
        } else {
            surgeFeePercentage = staticFeePercentage;
        }
    }

    function _isSurging(
        SurgeFeeData memory surgeFeeData,
        uint256[] memory currentBalances,
        uint256 newTotalImbalance
    ) internal pure returns (bool isSurging) {
        // If we are balanced, or the balance has improved, do not surge: simply return the regular fee percentage.
        if (newTotalImbalance == 0) {
            return false;
        }

        uint256 oldTotalImbalance = StableSurgeMedianMath.calculateImbalance(currentBalances);

        // Surging if imbalance grows and we're currently above the threshold.
        return (newTotalImbalance > oldTotalImbalance && newTotalImbalance > surgeFeeData.thresholdPercentage);
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

    function _ensureValidPercentage(uint256 percentage) private pure {
        if (percentage > FixedPoint.ONE) {
            revert InvalidPercentage();
        }
    }
}
