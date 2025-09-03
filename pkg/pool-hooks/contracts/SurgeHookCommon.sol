// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ISurgeHookCommon } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/ISurgeHookCommon.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

/**
 * @notice This is a base contract for surge hook implementations (e.g. E-CLP, Stable).
 * @dev Surge hooks compute a dynamic fee based on the imbalance of the pool. Contracts that inherit from this
 * contract must implement the _isSurgingSwap and _isSurgingUnbalancedLiquidity functions.
 */
abstract contract SurgeHookCommon is ISurgeHookCommon, BaseHooks, VaultGuard, SingletonAuthentication, Version {
    using FixedPoint for uint256;
    using SafeCast for *;

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
                              Functions to Implement
    ***************************************************************************/

    function _isSurgingSwap(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage,
        SurgeFeeData memory surgeFeeData
    ) internal view virtual returns (bool isSurging, uint256 newTotalImbalance);

    function _isSurgingUnbalancedLiquidity(
        address pool,
        uint256[] memory oldBalancesScaled18,
        uint256[] memory balancesScaled18
    ) internal view virtual returns (bool isSurging);

    /***************************************************************************
                                IHooks Functions
    ***************************************************************************/

    /// @inheritdoc IHooks
    function getHookFlags() public pure virtual override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public virtual override onlyVault returns (bool) {
        // Initially set the max pool surge percentage to the default (can be changed by the pool swapFeeManager
        // in the future).
        _setMaxSurgeFeePercentage(pool, _defaultMaxSurgeFeePercentage);

        // Initially set the pool threshold to the default (can be changed by the pool swapFeeManager in the future).
        _setSurgeThresholdPercentage(pool, _defaultSurgeThresholdPercentage);

        return true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view virtual override returns (bool, uint256) {
        return (true, computeSwapSurgeFeePercentage(params, pool, staticSwapFeePercentage));
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
    ) public view virtual override returns (bool success, uint256[] memory hookAdjustedAmountsInRaw) {
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
    ) public view virtual override returns (bool success, uint256[] memory hookAdjustedAmountsOutRaw) {
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
                            Surge Hook Functions
    ***************************************************************************/

    /// @inheritdoc ISurgeHookCommon
    function computeSwapSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view returns (uint256 surgeFeePercentage) {
        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];

        (bool isSurging, uint256 newTotalImbalance) = _isSurgingSwap(
            params,
            pool,
            staticSwapFeePercentage,
            surgeFeeData
        );

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

    /// @inheritdoc ISurgeHookCommon
    function isSurgingSwap(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) external view returns (bool isSurging) {
        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];

        (isSurging, ) = _isSurgingSwap(params, pool, staticSwapFeePercentage, surgeFeeData);
    }

    /***************************************************************************
                          Surge Hook Getters and Setters
    ***************************************************************************/

    /// @inheritdoc ISurgeHookCommon
    function getDefaultMaxSurgeFeePercentage() external view returns (uint256) {
        return _defaultMaxSurgeFeePercentage;
    }

    /// @inheritdoc ISurgeHookCommon
    function getDefaultSurgeThresholdPercentage() external view returns (uint256) {
        return _defaultSurgeThresholdPercentage;
    }

    /// @inheritdoc ISurgeHookCommon
    function getMaxSurgeFeePercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].maxSurgeFeePercentage;
    }

    /// @inheritdoc ISurgeHookCommon
    function getSurgeThresholdPercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].thresholdPercentage;
    }

    /// @inheritdoc ISurgeHookCommon
    function setMaxSurgeFeePercentage(
        address pool,
        uint256 newMaxSurgeSurgeFeePercentage
    ) external withValidPercentage(newMaxSurgeSurgeFeePercentage) onlySwapFeeManagerOrGovernance(pool) {
        _setMaxSurgeFeePercentage(pool, newMaxSurgeSurgeFeePercentage);
    }

    /// @inheritdoc ISurgeHookCommon
    function setSurgeThresholdPercentage(
        address pool,
        uint256 newSurgeThresholdPercentage
    ) external withValidPercentage(newSurgeThresholdPercentage) onlySwapFeeManagerOrGovernance(pool) {
        _setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    /***************************************************************************
                                  Private Functions
    ***************************************************************************/

    function _isSurging(
        uint64 thresholdPercentage,
        uint256 oldTotalImbalance,
        uint256 newTotalImbalance
    ) internal pure virtual returns (bool isSurging) {
        // If we are balanced, or the balance has improved, do not surge: simply return the regular fee percentage.
        if (newTotalImbalance == 0) {
            return false;
        }

        // Surging if imbalance grows and we're currently above the threshold.
        return (newTotalImbalance > oldTotalImbalance && newTotalImbalance > thresholdPercentage);
    }

    /// @dev Assumes the percentage value and sender have been externally validated.
    function _setMaxSurgeFeePercentage(address pool, uint256 newMaxSurgeFeePercentage) internal {
        // Still use SafeCast out of an abundance of caution.
        _surgeFeePoolData[pool].maxSurgeFeePercentage = newMaxSurgeFeePercentage.toUint64();

        emit MaxSurgeFeePercentageChanged(pool, newMaxSurgeFeePercentage);
    }

    /// @dev Assumes the percentage value and sender have been externally validated.
    function _setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) internal {
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
