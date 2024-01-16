// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "./IRateProvider.sol";
import { PoolCallbacks, LiquidityManagement } from "./VaultTypes.sol";

interface IVaultExtension {
    /*******************************************************************************
                        Pool Registration and Initialization
    *******************************************************************************/

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

    /**
     * @notice Registers a pool, associating it with its factory and the tokens it manages.
     * @dev A pool can opt-out of pausing by providing a zero value for the pause window, or allow pausing indefinitely
     * by providing a large value. (Pool pause windows are not limited by the Vault maximums.) The vault defines an
     * additional buffer period during which a paused pool will stay paused. After the buffer period passes, a paused
     * pool will automatically unpause.
     *
     * A pool can opt out of Balancer governance pausing by providing a custom `pauseManager`. This might be a
     * multi-sig contract or an arbitrary smart contract with its own access controls, that forwards calls to
     * the Vault.
     *
     * If the zero address is provided for the `pauseManager`, permissions for pausing the pool will default to the
     * authorizer.
     *
     * @param factory The factory address associated with the pool being registered
     * @param tokens An array of token addresses the pool will manage
     * @param rateProviders An array of rate providers corresponding to the tokens (or zero for tokens without rates)
     * @param pauseWindowEndTime The timestamp after which it is no longer possible to pause the pool
     * @param pauseManager Optional contract the Vault will allow to pause the pool
     * @param config Flags indicating which callbacks the pool supports
     * @param liquidityManagement Liquidity management flags with implemented methods
     */
    function registerPool(
        address factory,
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks calldata config,
        LiquidityManagement calldata liquidityManagement
    ) external;
}
