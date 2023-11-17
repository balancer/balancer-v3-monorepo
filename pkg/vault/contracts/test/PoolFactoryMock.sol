// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolCallbacks, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { FactoryWidePauseWindow } from "../factories/FactoryWidePauseWindow.sol";

contract PoolFactoryMock is FactoryWidePauseWindow {
    IVault private immutable _vault;

    constructor(IVault vault, uint256 pauseWindowDuration) FactoryWidePauseWindow(pauseWindowDuration) {
        _vault = vault;
    }

    function registerPool(
        address pool,
        IERC20[] memory tokens,
        address pauseManager,
        PoolCallbacks calldata poolCallbacks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokens,
            getNewPoolPauseWindowEndTime(),
            pauseManager,
            poolCallbacks,
            liquidityManagement
        );
    }

    // For tests; otherwise can't get the exact event arguments.
    function registerPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        address pauseManager,
        PoolCallbacks calldata poolCallbacks,
        LiquidityManagement calldata liquidityManagement,
        uint256 timestamp
    ) external {
        _vault.registerPool(pool, tokens, timestamp, pauseManager, poolCallbacks, liquidityManagement);
    }
}
