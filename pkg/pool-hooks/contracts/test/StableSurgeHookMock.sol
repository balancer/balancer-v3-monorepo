// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;


import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableSurgeHook } from "./../StableSurgeHook.sol";

contract StableSurgeHookMock is StableSurgeHook {
    constructor(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage
    ) StableSurgeHook(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage) {
    }

    function getSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticFeePercentage,
        uint256[] memory newBalances
    ) external view returns (uint256) {
        return _getSurgeFeePercentage(params, pool, staticFeePercentage, newBalances);
    }

    function isSurging(
        SurgeFeeData memory surgeFeeData,
        uint256[] memory currentBalances,
        uint256 newTotalImbalance
    ) external pure returns (bool) {
        return _isSurging(surgeFeeData, currentBalances, newTotalImbalance);
    }

    function getSurgeFeeData(address pool) external view returns (SurgeFeeData memory) {
        return _surgeFeePoolData[pool];
    }
}
