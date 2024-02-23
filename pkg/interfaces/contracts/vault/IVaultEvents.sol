// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "./IAuthorizer.sol";
import { LiquidityManagement, PoolHooks, TokenConfig } from "./VaultTypes.sol";

interface IVaultEvents {
    /**
     * @notice A Pool was registered by calling `registerPool`.
     * @param pool The pool being registered
     * @param factory The factory creating the pool
     * @param tokenConfig The pool's tokens
     * @param pauseWindowEndTime The pool's pause window end time
     * @param pauseManager The pool's external pause manager (or 0 for governance)
     * @param liquidityManagement Supported liquidity management hook flags
     */
    event PoolRegistered(
        address indexed pool,
        address indexed factory,
        TokenConfig[] tokenConfig,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolHooks hooks,
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
     * @param token The token in which the fee has been collected
     * @param amount The amount of the token collected as fees
     */
    event ProtocolFeeCollected(IERC20 indexed token, uint256 indexed amount);

    /**
     * @notice Emitted when a protocol swap fee is incurred.
     * @dev This is included for traceability of fees to pools. Pending protocol fees on both swap and yield are
     * combined. It is an invariant of the system that the total amounts for each token reported here and by
     * `ProtocolYieldFeeCharged`, summed over all pools, should equal the total collected for the token reported by
     * `ProtocolFeeCollected` when `collectProtocolFees` is called.
     *
     * @param pool The pool associated with this charge
     * @param token The token whose protocol fee balance increased
     * @param amount The amount of the protocol fee
     */
    event ProtocolSwapFeeCharged(address indexed pool, address indexed token, uint256 amount);

    /**
     * @notice Emitted when a protocol swap fee is incurred.
     * @dev This is included for traceability of fees to pools. Pending protocol fees on both swap and yield are
     * combined. It is an invariant of the system that the total amounts for each token reported here and by
     * `ProtocolSwapFeeCharged`, summed over all pools, should equal the total collected for the token reported by
     * `ProtocolFeeCollected` when `collectProtocolFees` is called.
     *
     * @param pool The pool associated with this charge
     * @param token The token whose protocol fee balance increased
     * @param amount The amount of the protocol fee
     */
    event ProtocolYieldFeeCharged(address indexed pool, address indexed token, uint256 amount);

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

    /**
     * @notice A new ERC4626BufferPoolFactory has been registered.
     * @dev Buffer Pools associated with wrapped tokens can now be created from this factory.
     * @param bufferPoolFactory The factory being registered
     */
    event BufferPoolFactoryRegistered(address indexed bufferPoolFactory);

    /**
     * @notice A new ERC4626BufferPoolFactory has been deregistered.
     * @dev This prevents new Buffer Pools from being created with this factory: `registerBuffer` calls
     * using will fail. Existing Buffer Pools (and associated regular pools) are unaffected.
     *
     * @param bufferPoolFactory The factory being registered
     */
    event BufferPoolFactoryDeregistered(address indexed bufferPoolFactory);

    /**
     * @notice A new ERC4626BufferPool has been created.
     * @param wrappedToken The wrapped token associated with the buffer
     * @param baseToken The base token associated with the wrapper
     */
    event WrappedTokenBufferCreated(address indexed wrappedToken, address indexed baseToken);
}
