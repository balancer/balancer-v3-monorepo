// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "./IRateProvider.sol";
import { PoolCallbacks, LiquidityManagement } from "./VaultTypes.sol";

interface IVaultEvents {
    /**
     * @notice A Pool was registered by calling `registerPool`.
     * @param pool The pool being registered
     * @param factory The factory creating the pool
     * @param tokens The pool's tokens
     * @param rateProviders The pool's rate providers (or zero)
     * @param pauseWindowEndTime The pool's pause window end time
     * @param pauseManager The pool's external pause manager (or 0 for governance)
     * @param liquidityManagement Supported liquidity management callback flags
     */
    event PoolRegistered(
        address indexed pool,
        address indexed factory,
        IERC20[] tokens,
        IRateProvider[] rateProviders,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks callbacks,
        LiquidityManagement liquidityManagement
    );
}
