// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { AddLiquidityKind, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

abstract contract PoolWithHooks is IPoolHooks {
    error CallerIsNotVault(address);

    IPoolHooks private immutable _hooks;
    IVault private immutable _vault;

    constructor(IVault vault, IPoolHooks hooks) {
        _hooks = hooks;
        _vault = vault;
    }

    /**
     * @notice Modifier to check that the caller is the vault.
     */
    modifier vaultOnly() {
        if (msg.sender != address(_vault)) {
            revert CallerIsNotVault(msg.sender);
        }

        _;
    }

    /**
     * @notice Returns the address of the hooks contract
     * @return The address of the hooks contract
     */
    function hooksAddress() external view returns (address) {
        return address(_hooks);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeInitialize(
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) external vaultOnly returns (bool) {
        return _hooks.onBeforeInitialize(exactAmountsIn, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) external vaultOnly returns (bool) {
        return _hooks.onAfterInitialize(exactAmountsIn, bptAmountOut, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeAddLiquidity(
        address sender,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external vaultOnly returns (bool success) {
        return
            _hooks.onBeforeAddLiquidity(
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
    ) external vaultOnly returns (bool success) {
        return _hooks.onAfterAddLiquidity(sender, amountsInScaled18, bptAmountOut, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeRemoveLiquidity(
        address sender,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external vaultOnly returns (bool success) {
        return
            _hooks.onBeforeRemoveLiquidity(
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
    ) external vaultOnly returns (bool success) {
        return
            _hooks.onAfterRemoveLiquidity(sender, bptAmountIn, amountsOutScaled18, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams memory params) external vaultOnly returns (bool success) {
        return _hooks.onBeforeSwap(params);
    }

    /// @inheritdoc IPoolHooks
    function onAfterSwap(
        IPoolHooks.AfterSwapParams memory params,
        uint256 amountCalculatedScaled18
    ) external vaultOnly returns (bool success) {
        return _hooks.onAfterSwap(params, amountCalculatedScaled18);
    }
}
