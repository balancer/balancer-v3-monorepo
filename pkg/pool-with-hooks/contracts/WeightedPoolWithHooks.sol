// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { AddLiquidityKind, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { IBaseDynamicFeePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBaseDynamicFeePool.sol";

import { PoolWithHooks } from "./PoolWithHooks.sol";

contract WeightedPoolWithHooks is WeightedPool, PoolWithHooks {
    constructor(
        NewPoolParams memory params,
        IVault vault,
        bytes memory hooksBytecode,
        bytes32 hooksSalt
    ) WeightedPool(params, vault) PoolWithHooks(hooksBytecode, hooksSalt) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IBaseDynamicFeePool).interfaceId || super.supportsInterface(interfaceId);
    }
}
