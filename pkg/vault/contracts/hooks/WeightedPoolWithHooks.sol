// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { AddLiquidityKind, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { PoolWithHooks } from "./PoolWithHooks.sol";

contract WeightedPoolWithHooks is WeightedPool, PoolWithHooks {
    constructor(
        NewPoolParams memory params,
        IVault vault,
        IPoolHooks hooks
    ) WeightedPool(params, vault) PoolWithHooks(vault, hooks) {}
}
