// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

/**
 * @dev Pools that only implement a subset of callbacks can inherit from here instead of IPoolCallbacks,
 * and only override what they need.
 */
abstract contract PoolCallbacks is IPoolCallbacks {
    /// @inheritdoc IPoolCallbacks
    function onBeforeInitialize(uint256[] memory, bytes memory) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolCallbacks
    function onAfterInitialize(uint256[] memory, uint256, bytes memory) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolCallbacks
    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolCallbacks
    function onBeforeRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolCallbacks
    function onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolCallbacks
    function onBeforeSwap(IBasePool.SwapParams calldata) external virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IPoolCallbacks
    function onAfterSwap(AfterSwapParams calldata, uint256) external virtual returns (bool) {
        return false;
    }
}
