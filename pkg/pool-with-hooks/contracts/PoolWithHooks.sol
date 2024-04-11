// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { AddLiquidityKind, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

abstract contract PoolWithHooks is IPoolHooks {
    IPoolHooks private immutable _hooksContract;

    constructor(bytes memory hooksBytecode, bytes32 hooksSalt) {
        // Deploy a hooks contract with create2
        // solhint-disable no-inline-assembly
        address deployedHooksAddress;
        assembly {
            deployedHooksAddress := create2(0, add(hooksBytecode, 0x20), mload(hooksBytecode), hooksSalt)
            if iszero(extcodesize(deployedHooksAddress)) {
                revert(0, 0)
            }
        }

        _hooksContract = IPoolHooks(deployedHooksAddress);
    }

    /**
     * @notice Returns the address of the hooks contract
     * @return The address of the hooks contract
     */
    function hooksAddress() external view returns (address) {
        return address(_hooksContract);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeInitialize(uint256[] memory exactAmountsIn, bytes memory userData) public virtual returns (bool) {
        return _hooksContract.onBeforeInitialize(exactAmountsIn, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) public virtual returns (bool) {
        return _hooksContract.onAfterInitialize(exactAmountsIn, bptAmountOut, userData);
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
            _hooksContract.onBeforeAddLiquidity(
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
        return _hooksContract.onAfterAddLiquidity(sender, amountsInScaled18, bptAmountOut, balancesScaled18, userData);
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
            _hooksContract.onBeforeRemoveLiquidity(
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
            _hooksContract.onAfterRemoveLiquidity(sender, bptAmountIn, amountsOutScaled18, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams memory params) public virtual returns (bool success) {
        return _hooksContract.onBeforeSwap(params);
    }

    /// @inheritdoc IPoolHooks
    function onAfterSwap(
        IPoolHooks.AfterSwapParams memory params,
        uint256 amountCalculatedScaled18
    ) public virtual returns (bool success) {
        return _hooksContract.onAfterSwap(params, amountCalculatedScaled18);
    }
}
