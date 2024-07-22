// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IAuthorizer } from "./IAuthorizer.sol";
import { IHooks } from "./IHooks.sol";
import { IProtocolFeeController } from "./IProtocolFeeController.sol";
import "./VaultTypes.sol";

/// @dev Events are declared inside an interface (namespace) to improve DX with Typechain.
interface IVaultEvents {
    /**
     * @notice A Pool was registered by calling `registerPool`.
     * @param pool The pool being registered
     * @param factory The factory creating the pool
     * @param tokenConfig An array of descriptors for the tokens the pool will manage
     * @param swapFeePercentage The static swap fee of the pool
     * @param pauseWindowEndTime The pool's pause window end time
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param hooksConfig Flags indicating which hooks the pool supports and address of hooks contract
     * @param liquidityManagement Supported liquidity management hook flags
     */
    event PoolRegistered(
        address indexed pool,
        address indexed factory,
        TokenConfig[] tokenConfig,
        uint256 swapFeePercentage,
        uint32 pauseWindowEndTime,
        PoolRoleAccounts roleAccounts,
        HooksConfig hooksConfig,
        LiquidityManagement liquidityManagement
    );

    /**
     * @notice A Pool was initialized by calling `initialize`.
     * @param pool The pool being initialized
     */
    event PoolInitialized(address indexed pool);

    /**
     * @notice A swap has occurred.
     * @param pool The pool with the tokens being swapped
     * @param tokenIn The token entering the Vault (balance increases)
     * @param tokenOut The token leaving the Vault (balance decreases)
     * @param amountIn Number of tokenIn tokens
     * @param amountOut Number of tokenOut tokens
     * @param swapFeePercentage Swap fee percentage applied (can differ if dynamic)
     * @param swapFeeAmount Swap fee amount paid
     * @param swapFeeToken Token the swap fee was paid in
     */
    event Swap(
        address indexed pool,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 swapFeePercentage,
        uint256 swapFeeAmount,
        IERC20 swapFeeToken
    );

    /**
     * @notice A wrap operation has occurred.
     * @param underlyingToken The underlying token address
     * @param wrappedToken The wrapped token address
     * @param depositedUnderlying Number of underlying tokens deposited
     * @param mintedShares Number of shares (wrapped tokens) minted
     */
    event Wrap(
        IERC20 indexed underlyingToken,
        IERC4626 indexed wrappedToken,
        uint256 depositedUnderlying,
        uint256 mintedShares
    );

    /**
     * @notice An unwrap operation has occurred.
     * @param wrappedToken The wrapped token address
     * @param underlyingToken The underlying token address
     * @param burnedShares Number of shares (wrapped tokens) burned
     * @param withdrawnUnderlying Number of underlying tokens withdrawn
     */
    event Unwrap(
        IERC4626 indexed wrappedToken,
        IERC20 indexed underlyingToken,
        uint256 burnedShares,
        uint256 withdrawnUnderlying
    );

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
     * @notice Emitted when the swap fee percentage of a pool is updated.
     * @param swapFeePercentage The new swap fee percentage for the pool
     */
    event SwapFeePercentageChanged(address indexed pool, uint256 swapFeePercentage);

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
     * @notice A new protocol fee controller is set by `setProtocolFeeController`.
     * @param newProtocolFeeController The address of the new protocol fee controller
     */
    event ProtocolFeeControllerChanged(IProtocolFeeController indexed newProtocolFeeController);

    /**
     * @notice Liquidity was added to an ERC4626 buffer.
     * @dev The underlying token can be derived from the wrapped token, so it's not included here. The shares are not
     * tokenized like pool BPT, but accounted for in the Vault. `getBufferOwnerShares` retrieves the current total
     * shares for a given buffer and address, and `getBufferTotalShares` returns the "totalSupply" of a buffer.
     *
     * @param wrappedToken The wrapped token that identifies the buffer
     * @param sharesOwner The address depositing the funds
     * @param amountWrapped The amount of the wrapped token that was deposited
     * @param amountUnderlying The amount of the underlying token that was deposited
     * @param issuedShares The "internal BPT" shares credited to the depositor
     */
    event LiquidityAddedToBuffer(
        IERC4626 indexed wrappedToken,
        address indexed sharesOwner,
        uint256 amountWrapped,
        uint256 amountUnderlying,
        uint256 issuedShares
    );

    /**
     * @notice Liquidity was removed from an ERC4626 buffer.
     * @dev The underlying token can be derived from the wrapped token, so it's not included here. The shares are not
     * tokenized like pool BPT, but accounted for in the Vault. `getBufferOwnerShares` retrieves the current total
     * shares for a given buffer and address, and `getBufferTotalShares` returns the "totalSupply" of a buffer.
     *
     * @param wrappedToken The wrapped token that identifies the buffer
     * @param sharesOwner The address withdrawing the funds
     * @param amountWrapped The amount of the wrapped token that was withdrawn
     * @param amountUnderlying The amount of the underlying token that was withdrawn
     * @param removedShares The "internal BPT" shares debited from the share owner
     */
    event LiquidityRemovedFromBuffer(
        IERC4626 indexed wrappedToken,
        address indexed sharesOwner,
        uint256 amountWrapped,
        uint256 amountUnderlying,
        uint256 removedShares
    );
}
