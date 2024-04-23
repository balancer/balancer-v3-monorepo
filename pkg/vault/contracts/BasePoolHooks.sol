// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { AddLiquidityKind, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @dev Pools that only implement a subset of callbacks can inherit from here instead of IPoolHooks,
 * and only override what they need.
 */
abstract contract BasePoolHooks is IPoolHooks {
    /// @inheritdoc IPoolHooks
    function onBeforeInitialize(uint256[] memory, bytes memory) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onAfterInitialize(uint256[] memory, uint256, bytes memory) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onBeforeAddLiquidity(
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onBeforeRemoveLiquidity(
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams calldata) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onAfterSwap(AfterSwapParams calldata, uint256) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolHooks
    function onComputeDynamicSwapFee(IBasePool.PoolSwapParams calldata) external view virtual returns (bool, uint256) {
        return (false, 0);
    }
}
