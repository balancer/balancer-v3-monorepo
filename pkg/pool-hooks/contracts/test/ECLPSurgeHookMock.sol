// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

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

    function getSwapSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticFeePercentage,
        uint256[] memory newBalances,
        IGyroECLPPool.EclpParams memory eclpParams,
        int256 a,
        int256 b
    ) external view returns (uint256) {
        return _getSwapSurgeFeePercentage(params, pool, staticFeePercentage, newBalances, eclpParams, a, b);
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
}
