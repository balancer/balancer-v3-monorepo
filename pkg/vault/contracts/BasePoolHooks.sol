// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "./VaultGuard.sol";

/**
 * @dev Pools that only implement a subset of callbacks can inherit from here instead of IHooks,
 * and only override what they need.
 */
abstract contract BasePoolHooks is IHooks, VaultGuard {
    HooksConfig internal _hooksConfig;

    constructor(IVault vault) VaultGuard(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) external virtual onlyVault returns (bool) {
        // By default, deny all factories. This method must be overwritten by the hook contract
        return false;
    }

    /// @inheritdoc IHooks
    function getHooksConfig() external virtual returns (HooksConfig memory) {
        return _hooksConfig;
    }

    /// @inheritdoc IHooks
    function onBeforeInitialize(uint256[] memory, bytes memory) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterInitialize(uint256[] memory, uint256, bytes memory) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onBeforeAddLiquidity(
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onBeforeRemoveLiquidity(
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onBeforeSwap(IBasePool.PoolSwapParams calldata) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(AfterSwapParams calldata, uint256) external virtual onlyVault returns (bool) {
        return false;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams calldata
    ) external view virtual onlyVault returns (bool, uint256) {
        return (false, 0);
    }
}
