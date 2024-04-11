// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import {
    AddLiquidityKind,
    PoolHooks,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooks } from "../BaseHooks.sol";

contract MockHooks is BaseHooks {
    event HookCalled(string hookName);

    function availableHooks() external pure override returns (PoolHooks memory) {
        return
            PoolHooks({
                shouldCallBeforeInitialize: true,
                shouldCallAfterInitialize: true,
                shouldCallBeforeAddLiquidity: true,
                shouldCallAfterAddLiquidity: true,
                shouldCallBeforeRemoveLiquidity: true,
                shouldCallAfterRemoveLiquidity: true,
                shouldCallBeforeSwap: true,
                shouldCallAfterSwap: true
            }); // All hooks enabled
    }

    function supportsDynamicFee() external pure override returns (bool) {
        return false;
    }

    function _onBeforeInitialize(uint256[] memory, bytes memory) internal override returns (bool) {
        // Custom logic before initialize
        emit HookCalled("onBeforeInitialize");
        return true;
    }

    function _onAfterInitialize(uint256[] memory, uint256, bytes memory) internal override returns (bool) {
        // Custom logic after initialize
        emit HookCalled("onAfterInitialize");
        return true;
    }

    function _onBeforeAddLiquidity(
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) internal override returns (bool) {
        // Custom logic before add liquidity
        emit HookCalled("onBeforeAddLiquidity");
        return true;
    }

    function _onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) internal override returns (bool) {
        // Custom logic after add liquidity
        emit HookCalled("onAfterAddLiquidity");
        return true;
    }

    function _onBeforeRemoveLiquidity(
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) internal override returns (bool) {
        // Custom logic before remove liquidity
        emit HookCalled("onBeforeRemoveLiquidity");
        return true;
    }

    function _onAfterRemoveLiquidity(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) internal override returns (bool) {
        // Custom logic after remove liquidity
        emit HookCalled("onAfterRemoveLiquidity");
        return true;
    }

    function _onBeforeSwap(IBasePool.PoolSwapParams memory) internal override returns (bool) {
        // Custom logic before swap
        emit HookCalled("onBeforeSwap");
        return true;
    }

    function _onAfterSwap(IPoolHooks.AfterSwapParams memory, uint256) internal override returns (bool) {
        // Custom logic after swap
        emit HookCalled("onAfterSwap");
        return true;
    }
}
