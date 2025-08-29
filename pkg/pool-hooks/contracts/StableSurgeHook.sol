// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { StableSurgeMedianMath } from "./utils/StableSurgeMedianMath.sol";
import { SurgeHookCommon } from "./SurgeHookCommon.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a "surge" fee on trades that unbalance the pool beyond the threshold.
 */
contract StableSurgeHook is SurgeHookCommon {
    /**
     * @notice A new `StableSurgeHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event StableSurgeHookRegistered(address indexed pool, address indexed factory);

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

        emit StableSurgeHookRegistered(pool, factory);
    }

    /***************************************************************************
                                Surge Hook Functions
    ***************************************************************************/

    function _isSurgingSwap(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage,
        SurgeFeeData memory surgeFeeData
    ) internal view override returns (bool isSurging, uint256 newTotalImbalance) {
        // If the max surge fee percentage is less than the static fee percentage, return the static fee percentage.
        // No matter where the imbalance is, the fee can never be smaller than the static fee.
        if (surgeFeeData.maxSurgeFeePercentage < staticSwapFeePercentage) {
            return (false, 0);
        }

        uint256 amountCalculatedScaled18 = StablePool(pool).onSwap(params);

        uint256[] memory newBalancesScaled18 = new uint256[](params.balancesScaled18.length);
        ScalingHelpers.copyToArray(params.balancesScaled18, newBalancesScaled18);

        if (params.kind == SwapKind.EXACT_IN) {
            newBalancesScaled18[params.indexIn] += params.amountGivenScaled18;
            newBalancesScaled18[params.indexOut] -= amountCalculatedScaled18;
        } else {
            newBalancesScaled18[params.indexIn] += amountCalculatedScaled18;
            newBalancesScaled18[params.indexOut] -= params.amountGivenScaled18;
        }

        uint256 oldTotalImbalance = StableSurgeMedianMath.calculateImbalance(params.balancesScaled18);
        newTotalImbalance = StableSurgeMedianMath.calculateImbalance(newBalancesScaled18);

        isSurging = _isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance);
    }

    function _isSurgingUnbalancedLiquidity(
        address pool,
        uint256[] memory oldBalancesScaled18,
        uint256[] memory balancesScaled18
    ) internal view override returns (bool isSurging) {
        SurgeFeeData memory surgeFeeData = _surgeFeePoolData[pool];

        uint256 oldTotalImbalance = StableSurgeMedianMath.calculateImbalance(oldBalancesScaled18);
        uint256 newTotalImbalance = StableSurgeMedianMath.calculateImbalance(balancesScaled18);

        isSurging = _isSurging(surgeFeeData.thresholdPercentage, oldTotalImbalance, newTotalImbalance);
    }

    /***************************************************************************
                                  Legacy Functions
    ***************************************************************************/

    /**
     * @notice Computes the surge fee percentage for a given swap.
     * @dev This function is deprecated and `computeSwapSurgeFeePercentage` should be used instead. Since there are
     * solutions already using this function, we should keep it.
     * @param params The parameters of the swap
     * @param pool The pool on which the swap is being performed
     * @param staticSwapFeePercentage The static swap fee percentage
     * @return surgeFeePercentage The surge fee percentage
     */
    function getSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view returns (uint256 surgeFeePercentage) {
        return computeSwapSurgeFeePercentage(params, pool, staticSwapFeePercentage);
    }
}
