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
        bytes memory hooksBytecode,
        bytes32 hooksSalt
    ) WeightedPool(params, vault) PoolWithHooks(hooksBytecode, hooksSalt) {}

    function onBeforeInitialize(
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) public override onlyVault returns (bool) {
        return super.onBeforeInitialize(exactAmountsIn, userData);
    }

    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) public override onlyVault returns (bool) {
        return super.onAfterInitialize(exactAmountsIn, bptAmountOut, userData);
    }

    function onBeforeAddLiquidity(
        address sender,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public override onlyVault returns (bool success) {
        return
            super.onBeforeAddLiquidity(sender, kind, maxAmountsInScaled18, minBptAmountOut, balancesScaled18, userData);
    }

    function onAfterAddLiquidity(
        address sender,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public override onlyVault returns (bool success) {
        return super.onAfterAddLiquidity(sender, amountsInScaled18, bptAmountOut, balancesScaled18, userData);
    }

    function onBeforeRemoveLiquidity(
        address sender,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public override onlyVault returns (bool success) {
        return
            super.onBeforeRemoveLiquidity(
                sender,
                kind,
                maxBptAmountIn,
                minAmountsOutScaled18,
                balancesScaled18,
                userData
            );
    }

    function onAfterRemoveLiquidity(
        address sender,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public override onlyVault returns (bool success) {
        return super.onAfterRemoveLiquidity(sender, bptAmountIn, amountsOutScaled18, balancesScaled18, userData);
    }

    function onBeforeSwap(IBasePool.PoolSwapParams memory params) public override onlyVault returns (bool success) {
        return super.onBeforeSwap(params);
    }

    function onAfterSwap(
        IPoolHooks.AfterSwapParams memory params,
        uint256 amountCalculatedScaled18
    ) public override onlyVault returns (bool success) {
        return super.onAfterSwap(params, amountCalculatedScaled18);
    }
}
