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
     * @param tokens The pool's tokens
     * @param deltas The amount each token changed
     */
    event PoolBalanceChanged(address indexed pool, address indexed liquidityProvider, IERC20[] tokens, int256[] deltas);

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
    event ProtocolSwapFeePercentageChanged(uint256 indexed swapFeePercentage);

    /**
     * @notice Emitted when the protocol yield fee percentage is updated.
     * @param yieldFeePercentage The updated protocol yield fee percentage
     */
    event ProtocolYieldFeePercentageChanged(uint256 indexed yieldFeePercentage);

    /**
     * @notice Logs the collection of fees in a specific token and amount.
     * @param pool A pool that has collected protocol fees
     * @param token The token in which the fee has been collected
     * @param amount The amount of the token collected as fees
     */
    event ProtocolFeeCollected(address pool, IERC20 indexed token, uint256 indexed amount);

    /**
     * @notice Emitted when a protocol swap fee is incurred.
     * @dev This is included for offchain traceability of fees to pools. Pending protocol fees on both swap and yield
     * are combined. It is an invariant of the system that the total amounts for each token reported here and by
     * `ProtocolYieldFeeCharged` should equal the total collected for the token and pool reported by
     * `ProtocolFeeCollected` when `collectProtocolFees` is called.
     *
     * @param pool The pool associated with this charge
     * @param token The token whose protocol fee balance increased
     * @param amount The amount of the protocol fee
     */
    event ProtocolSwapFeeCharged(address indexed pool, address indexed token, uint256 amount);

    /**
     * @notice Emitted when a protocol yield fee is incurred.
     * @dev This is included for offchain traceability of fees to pools. Pending protocol fees on both swap and yield
     * are combined. It is an invariant of the system that the total amounts for each token reported here and by
     * `ProtocolSwapFeeCharged` should equal the total collected for the token and pool reported by
     * `ProtocolFeeCollected` when `collectProtocolFees` is called.
     *
     * @param pool The pool associated with this charge
     * @param token The token whose protocol fee balance increased
     * @param amount The amount of the protocol fee
     */
    event ProtocolYieldFeeCharged(address indexed pool, address indexed token, uint256 amount);

    /**
     * @notice Emitted when the swap fee percentage of a pool is updated.
     * @param swapFeePercentage The new swap fee percentage for the pool
     */
    event SwapFeePercentageChanged(address indexed pool, uint256 indexed swapFeePercentage);

    /**
     * @notice Emitted when the pool creator fee percentage of a pool is updated.
     * @param poolCreatorFeePercentage The new pool creator fee percentage for the pool
     */
    event PoolCreatorFeePercentageChanged(address indexed pool, uint256 indexed poolCreatorFeePercentage);

    /**
     * @notice Emitted when a creator swap fee is incurred.
     * @dev This is included for traceability of fees to pools. Pending creator fees on both swap and yield are
     * combined. It is an invariant of the system that the total amounts for each token reported here and by
     * `PoolCreatorYieldFeeCharged` should equal the total collected for the token and pool reported by
     * `PoolCreatorFeeCollected` when `collectPoolCreatorFees` is called.
     *
     * @param pool The pool associated with this charge
     * @param token The token whose pool creator fee balance increased
     * @param amount The amount of the pool creator fee
     */
    event PoolCreatorSwapFeeCharged(address indexed pool, address indexed token, uint256 amount);

    /**
     * @notice Emitted when a creator yield fee is incurred.
     * @dev This is included for traceability of fees to pools. Pending creator fees on both swap and yield are
     * combined. It is an invariant of the system that the total amounts for each token reported here and by
     * `PoolCreatorSwapFeeCharged` should equal the total collected for the token and pool reported by
     * `PoolCreatorFeeCollected` when `collectPoolCreatorFees` is called.
     *
     * @param pool The pool associated with this charge
     * @param token The token whose pool creator fee balance increased
     * @param amount The amount of the pool creator fee
     */
    event PoolCreatorYieldFeeCharged(address indexed pool, address indexed token, uint256 amount);

    /**
     * @notice Logs the collection of pool creator fees in a specific pool, by token and amount.
     * @param pool The address of the pool for which the fee has been collected
     * @param token The token in which the fee has been collected
     * @param amount The amount of the token collected in fees
     */
    event PoolCreatorFeeCollected(address pool, IERC20 indexed token, uint256 indexed amount);

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
