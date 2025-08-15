// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableSurgeHook } from "./../StableSurgeHook.sol";

contract StableSurgeHookMock is StableSurgeHook {
    constructor(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage,
        string memory version
    ) StableSurgeHook(vault, defaultMaxSurgeFeePercentage, defaultSurgeThresholdPercentage, version) {
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
}
