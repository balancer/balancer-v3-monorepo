// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import {
    AddLiquidityKind,
    HookFlags,
    LiquidityManagement,
    RemoveLiquidityKind,
    TokenConfig,
    PoolSwapParams,
    AfterSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "./VaultGuard.sol";

/**
 * @notice Base for pool hooks contracts.
 * @dev Hook contracts that only implement a subset of callbacks can inherit from here instead of IHooks,
 * and only override what they need. `VaultGuard` allows use of the `onlyVault` modifier, which isn't used
 * in this abstract contract, but should be used in real derived hook contracts.
 */
abstract contract BaseHooks is IHooks, VaultGuard {
    constructor(IVault vault) VaultGuard(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public virtual returns (bool) {
        // By default, deny all factories. This method must be overwritten by the hook contract
        return false;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public view virtual returns (HookFlags memory);

    /// @inheritdoc IHooks
    function onBeforeInitialize(uint256[] memory, bytes memory) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterInitialize(uint256[] memory, uint256, bytes memory) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onBeforeAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool, uint256[] memory) {
        return (false, amountsInRaw);
    }

    /// @inheritdoc IHooks
    function onBeforeRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool, uint256[] memory) {
        return (false, amountsOutRaw);
    }

    /// @inheritdoc IHooks
    function onBeforeSwap(PoolSwapParams calldata, address) public virtual returns (bool) {
        // return false to trigger an error if shouldCallBeforeSwap is true but this function is not overridden.
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(AfterSwapParams calldata) public virtual returns (bool, uint256) {
        // return false to trigger an error if shouldCallAfterSwap is true but this function is not overridden.
        // The second argument is not used.
        return (false, 0);
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata,
        address,
        uint256
    ) public view virtual returns (bool, uint256) {
        return (false, 0);
    }
}
