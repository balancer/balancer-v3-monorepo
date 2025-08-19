// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

import { ECLPSurgeHook } from "./../ECLPSurgeHook.sol";

contract ECLPSurgeHookMock is ECLPSurgeHook {
    constructor(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) ECLPSurgeHook(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function isSurging(
        uint64 thresholdPercentage,
        uint256 oldTotalImbalance,
        uint256 newTotalImbalance
    ) external pure returns (bool) {
        return _isSurging(thresholdPercentage, oldTotalImbalance, newTotalImbalance);
    }

    function getSurgeFeeData(address pool) external view returns (SurgeFeeData memory) {
        return _surgeFeePoolData[pool];
    }

    function computePriceFromBalances(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
    ) external pure returns (uint256) {
        (int256 a, int256 b) = _computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
        return _computePrice(balancesScaled18, eclpParams, a, b);
    }

    function computeImbalanceNoSlope(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        int256 a,
        int256 b
    ) external pure returns (uint256 imbalance) {
        ImbalanceSlopeData memory imbalanceSlopeData = ImbalanceSlopeData({
            imbalanceSlopeBelowPeak: 1e18,
            imbalanceSlopeAbovePeak: 1e18
        });
        return _computeImbalance(balancesScaled18, eclpParams, a, b, imbalanceSlopeData);
    }

    function computeSwap(
        PoolSwapParams memory request,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
    ) external pure returns (uint256 amountCalculatedScaled18, int256 a, int256 b) {
        return _computeSwap(request, eclpParams, derivedECLPParams);
    }

    function computeOffsetFromBalances(
        uint256[] memory balancesScaled18,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedECLPParams
    ) external pure returns (int256 a, int256 b) {
        return _computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);
    }

    function computeImbalanceFromBalancesNoSlope(
        GyroECLPPool pool,
        uint256[] memory balancesScaled18
    ) external view returns (uint256 imbalance) {
        (IGyroECLPPool.EclpParams memory eclpParams, IGyroECLPPool.DerivedEclpParams memory derivedECLPParams) = pool
            .getECLPParams();
        (int256 a, int256 b) = _computeOffsetFromBalances(balancesScaled18, eclpParams, derivedECLPParams);

        ImbalanceSlopeData memory imbalanceSlopeData = ImbalanceSlopeData({
            imbalanceSlopeBelowPeak: 1e18,
            imbalanceSlopeAbovePeak: 1e18
        });

        return _computeImbalance(balancesScaled18, eclpParams, a, b, imbalanceSlopeData);
    }

    function manualSetSurgeMaxFeePercentage(address pool, uint256 newMaxSurgeFeePercentage) external {
        _setMaxSurgeFeePercentage(pool, newMaxSurgeFeePercentage);
    }
}
