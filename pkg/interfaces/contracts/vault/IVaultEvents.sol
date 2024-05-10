// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "./IAuthorizer.sol";
import { LiquidityManagement, PoolHooks, PoolRoleAccounts, TokenConfig } from "./VaultTypes.sol";

interface IVaultEvents {
    /**
     * @notice A Pool was registered by calling `registerPool`.
     * @param pool The pool being registered
     * @param factory The factory creating the pool
     * @param tokenConfig The pool's tokens
     * @param pauseWindowEndTime The pool's pause window end time
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param poolHooks Flags indicating which hooks the pool supports
     * @param liquidityManagement Supported liquidity management hook flags
     */
    event PoolRegistered(
        address indexed pool,
        address indexed factory,
        TokenConfig[] tokenConfig,
        uint256 pauseWindowEndTime,
        PoolRoleAccounts roleAccounts,
        PoolHooks poolHooks,
        LiquidityManagement liquidityManagement
    );

    /**
     * @notice A Pool was initialized by calling `initialize`.
     * @param pool The pool being initialized
     */
    event PoolInitialized(address indexed pool);

    /**
     * @notice Pool balances have changed (e.g., after initialization, add/remove liquidity).
     * @param pool The pool being registered
     * @param liquidityProvider The user performing the operation
     * @param deltas The amount each token changed, sorted in the pool tokens' order
     */
    event PoolBalanceChanged(address indexed pool, address indexed liquidityProvider, int256[] deltas);

    /**
     * @dev The Vault's pause status has changed.
     * @param paused True if the Vault was paused
     */
    event VaultPausedStateChanged(bool paused);

    /**
     * @dev A Pool's pause status has changed.
     * @param pool The pool that was just paused or unpaused
     * @param paused True if the pool was paused
     */
    event PoolPausedStateChanged(address indexed pool, bool paused);

    /**
     * @notice Emitted when the protocol swap fee percentage is updated.
     * @param swapFeePercentage The updated protocol swap fee percentage
     */
    event ProtocolSwapFeePercentageChanged(uint256 swapFeePercentage);

    /**
     * @notice Emitted when the protocol yield fee percentage is updated.
     * @param yieldFeePercentage The updated protocol yield fee percentage
     */
    event ProtocolYieldFeePercentageChanged(uint256 yieldFeePercentage);

    /**
     * @notice Logs the collection of protocol swap fees in a specific token and amount.
     * @param pool The pool on which the swap fee was charged
     * @param token The token in which the swap fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolSwapFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @notice Logs the collection of protocol yield fees in a specific token and amount.
     * @param pool The pool on which the yield fee was charged
     * @param token The token in which the yield fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolYieldFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @notice Emitted when the swap fee percentage of a pool is updated.
     * @param swapFeePercentage The new swap fee percentage for the pool
     */
    event SwapFeePercentageChanged(address indexed pool, uint256 swapFeePercentage);

    /**
     * @notice Emitted when the pool creator fee percentage of a pool is updated.
     * @param poolCreatorFeePercentage The new pool creator fee percentage for the pool
     */
    event PoolCreatorFeePercentageChanged(address indexed pool, uint256 poolCreatorFeePercentage);

    /**
     * @notice Logs the collection of pool creator swap fees in a specific pool, by token and amount.
     * @param pool The address of the pool on which the swap fee was collected
     * @param token The token in which the swap fee was collected
     * @param amount The amount of the token collected in fees
     */
    event PoolCreatorSwapFeeCollected(address pool, IERC20 indexed token, uint256 amount);

    /**
     * @notice Logs the collection of pool creator yield fees in a specific pool, by token and amount.
     * @param pool The address of the pool on which the yield fee was collected
     * @param token The token in which the yield fee was collected
     * @param amount The amount of the token collected in fees
     */
    event PoolCreatorYieldFeeCollected(address pool, IERC20 indexed token, uint256 amount);

    /**
     * @dev Recovery mode has been enabled or disabled for a pool.
     * @param pool The pool
     * @param recoveryMode True if recovery mode was enabled
     */
    event PoolRecoveryModeStateChanged(address indexed pool, bool recoveryMode);

    /**
     * @notice A new authorizer is set by `setAuthorizer`.
     * @param newAuthorizer The address of the new authorizer
     */
    event AuthorizerChanged(IAuthorizer indexed newAuthorizer);
}
