// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { AddLiquidityKind, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { SwapLocals } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { PoolData } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBaseDynamicFeePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBaseDynamicFeePool.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

abstract contract PoolWithHooks is IPoolHooks {
    IPoolHooks private immutable hooksContract;

    constructor(bytes memory hooksBytecode, bytes32 hooksSalt) {
        // Deploy a hooks contract with create2
        address deployedHooksAddress;
        assembly {
            deployedHooksAddress := create2(0, add(hooksBytecode, 0x20), mload(hooksBytecode), hooksSalt)
            if iszero(extcodesize(deployedHooksAddress)) {
                revert(0, 0)
            }
        }

        hooksContract = IPoolHooks(deployedHooksAddress);
    }

    /**
     * @notice Returns the address of the hooks contract
     * @return The address of the hooks contract
     */
    function hooksAddress() external view returns (address) {
        return address(hooksContract);
    }

    function computeFee(PoolData memory poolData, SwapLocals memory vars) external returns (uint256) {
        return hooksContract.computeFee(poolData, vars);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeInitialize(uint256[] memory exactAmountsIn, bytes memory userData) public virtual returns (bool) {
        return hooksContract.onBeforeInitialize(exactAmountsIn, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) public virtual returns (bool) {
        return hooksContract.onAfterInitialize(exactAmountsIn, bptAmountOut, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeAddLiquidity(
        address sender,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public virtual returns (bool success) {
        return
            hooksContract.onBeforeAddLiquidity(
                sender,
                kind,
                maxAmountsInScaled18,
                minBptAmountOut,
                balancesScaled18,
                userData
            );
    }

    /// @inheritdoc IPoolHooks
    function onAfterAddLiquidity(
        address sender,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public virtual returns (bool success) {
        return hooksContract.onAfterAddLiquidity(sender, amountsInScaled18, bptAmountOut, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeRemoveLiquidity(
        address sender,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public virtual returns (bool success) {
        return
            hooksContract.onBeforeRemoveLiquidity(
                sender,
                kind,
                maxBptAmountIn,
                minAmountsOutScaled18,
                balancesScaled18,
                userData
            );
    }

    /// @inheritdoc IPoolHooks
    function onAfterRemoveLiquidity(
        address sender,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public virtual returns (bool success) {
        return
            hooksContract.onAfterRemoveLiquidity(sender, bptAmountIn, amountsOutScaled18, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams memory params) public virtual returns (bool success) {
        return hooksContract.onBeforeSwap(params);
    }

    /// @inheritdoc IPoolHooks
    function onAfterSwap(
        IPoolHooks.AfterSwapParams memory params,
        uint256 amountCalculatedScaled18
    ) public virtual returns (bool success) {
        return hooksContract.onAfterSwap(params, amountCalculatedScaled18);
    }
}
