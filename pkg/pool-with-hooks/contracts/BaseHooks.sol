// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import {
    AddLiquidityKind,
    PoolHooks,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

abstract contract BaseHooks is IPoolHooks {
    error SenderIsNotPool(address);

    address public immutable authorizedPool;

    constructor() {
        authorizedPool = msg.sender;
    }

    /**
     * @notice Modifier to check that the sender is the authorized pool.
     */
    modifier onlyPool() {
        if (msg.sender != authorizedPool) {
            revert SenderIsNotPool(msg.sender);
        }
        _;
    }

    /**
     * @notice Returns the available hooks.
     * @dev This function should be overridden by derived contracts to return the hooks they support.
     * @return PoolHooks
     */
    function availableHooks() external pure virtual returns (PoolHooks memory);

    /// @inheritdoc IPoolHooks
    function onBeforeInitialize(
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) external onlyPool returns (bool) {
        return _onBeforeInitialize(exactAmountsIn, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) external onlyPool returns (bool) {
        return _onAfterInitialize(exactAmountsIn, bptAmountOut, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeAddLiquidity(
        address sender,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external onlyPool returns (bool success) {
        return _onBeforeAddLiquidity(sender, kind, maxAmountsInScaled18, minBptAmountOut, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterAddLiquidity(
        address sender,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external onlyPool returns (bool success) {
        return _onAfterAddLiquidity(sender, amountsInScaled18, bptAmountOut, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeRemoveLiquidity(
        address sender,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external onlyPool returns (bool success) {
        return
            _onBeforeRemoveLiquidity(sender, kind, maxBptAmountIn, minAmountsOutScaled18, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onAfterRemoveLiquidity(
        address sender,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external onlyPool returns (bool success) {
        return _onAfterRemoveLiquidity(sender, bptAmountIn, amountsOutScaled18, balancesScaled18, userData);
    }

    /// @inheritdoc IPoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams memory params) external onlyPool returns (bool success) {
        return _onBeforeSwap(params);
    }

    /// @inheritdoc IPoolHooks
    function onAfterSwap(
        IPoolHooks.AfterSwapParams memory params,
        uint256 amountCalculatedScaled18
    ) external onlyPool returns (bool success) {
        return _onAfterSwap(params, amountCalculatedScaled18);
    }

    /*******************************************************************************************************
            Default function implementations.
            Derived contracts should overwrite the corresponding functions for their supported hooks.
    *******************************************************************************************************/

    function _onBeforeInitialize(
        uint256[] memory, // exactAmountsIn
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterInitialize(
        uint256[] memory, // exactAmountsIn
        uint256, // bptAmountOut
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onBeforeAddLiquidity(
        address, // sender
        AddLiquidityKind, // kind
        uint256[] memory, // maxAmountsInScaled18
        uint256, // minBptAmountOut
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterAddLiquidity(
        address, // sender
        uint256[] memory, // amountsInScaled18
        uint256, // bptAmountOut
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onBeforeRemoveLiquidity(
        address, // sender
        RemoveLiquidityKind, // kind
        uint256, // maxBptAmountIn
        uint256[] memory, // minAmountsOutScaled18
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterRemoveLiquidity(
        address, // sender
        uint256, // bptAmountIn
        uint256[] memory, // amountsOutScaled18
        uint256[] memory, // balancesScaled18
        bytes memory // userData
    ) internal virtual returns (bool) {
        return false;
    }

    function _onBeforeSwap(
        IBasePool.PoolSwapParams memory // params
    ) internal virtual returns (bool) {
        return false;
    }

    function _onAfterSwap(
        IPoolHooks.AfterSwapParams memory, // params
        uint256 // amountCalculatedScaled18
    ) internal virtual returns (bool) {
        return false;
    }
}
