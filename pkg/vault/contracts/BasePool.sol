// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";

import { ERC20PoolToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20PoolToken.sol";

/// @notice Reference implementation for the base layer of a Pool contract.
abstract contract BasePool is IBasePool, IPoolCallbacks, IPoolLiquidity, ERC20PoolToken {
    IVault internal immutable _vault;

    constructor(IVault vault, string memory name, string memory symbol) ERC20PoolToken(vault, name, symbol) {
        _vault = vault;
    }

    /*******************************************************************************
                                     Callbacks
    *******************************************************************************/

    /// @notice Callback performed after a swap. Reverts here if configured but unimplemented.
    function onAfterSwap(SwapParams calldata, uint256) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /// @inheritdoc IPoolCallbacks
    function onBeforeAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    /// @inheritdoc IPoolLiquidity
    function onAddLiquidityCustom(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view virtual returns (uint256[] memory, uint256, bytes memory) {
        revert CallbackNotImplemented();
    }

    /// @inheritdoc IPoolCallbacks
    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /// @inheritdoc IPoolCallbacks
    function onBeforeRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    /// @inheritdoc IPoolLiquidity
    function onRemoveLiquidityCustom(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view virtual returns (uint256, uint256[] memory, bytes memory) {
        revert CallbackNotImplemented();
    }

    /// @inheritdoc IPoolCallbacks
    function onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }
}
