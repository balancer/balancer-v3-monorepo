// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*******************************************************************************
                        Registration and Initialization
*******************************************************************************/

/**
 * @dev A pool has already been registered. `registerPool` may only be called once.
 * @param pool The already registered pool
 */
error PoolAlreadyRegistered(address pool);

/**
 * @dev A pool has already been initialized. `initialize` may only be called once.
 * @param pool The already initialized pool
 */
error PoolAlreadyInitialized(address pool);

/**
 * @dev A pool has not been registered.
 * @param pool The unregistered pool
 */
error PoolNotRegistered(address pool);

/**
 * @dev A referenced pool has not been initialized.
 * @param pool The uninitialized pool
 */
error PoolNotInitialized(address pool);

/**
 * @dev A token was already registered (i.e., it is a duplicate in the pool).
 * @param token The duplicate token
 */
error TokenAlreadyRegistered(address token);

/// @dev An ERC4626 token's underlying base token conflicts was already registered.
error AmbiguousPoolToken(IERC20 token);

/// @dev The token count is below the minimum allowed.
error MinTokens();

/// @dev The token count is above the maximum allowed.
error MaxTokens();

/// @dev Invalid tokens (e.g., zero) cannot be registered.
error InvalidToken();

/// @dev The token type given in a TokenConfig during pool registration is invalid.
error InvalidTokenType();

/// @dev The data in a TokenConfig struct is inconsistent or unsupported.
error InvalidTokenConfiguration();

/// @dev A referenced token buffer has not been registered.
error WrappedTokenBufferNotRegistered();

/// @dev A token buffer can only be registered once.
error WrappedTokenBufferAlreadyRegistered();

/// @dev Caller has insufficient shares to make a withdrawal.
error InsufficientSharesForBufferWithdrawal();

/**
 * @dev The token list passed into an operation does not match the pool tokens in the pool.
 * @param pool Address of the pool
 * @param expectedToken The correct token at a given index in the pool
 * @param actualToken The actual token found at that index
 */
error TokensMismatch(address pool, address expectedToken, address actualToken);

/*******************************************************************************
                             Transient Accounting
*******************************************************************************/

/// @dev A transient accounting operation completed with outstanding token deltas.
error BalanceNotSettled();

/**
 * @dev In transient accounting, a handler is attempting to execute an operation out of order.
 * The caller address should equal the handler.
 * @param handler Address of the current handler being processed
 * @param caller Address of the caller (msg.sender)
 */
error WrongHandler(address handler, address caller);

/// @dev A user called a Vault function (swap, add/remove liquidity) outside the invoke context.
error NoHandler();

/**
 * @dev The caller attempted to access a handler at an invalid index.
 * @param index The invalid index
 */
error HandlerOutOfBounds(uint256 index);

/// @dev The pool has returned false to a callback, indicating the transaction should revert.
error CallbackFailed();

/// @dev An unauthorized Router tried to call a permissioned function (i.e., using the Vault's token allowance).
error RouterNotTrusted();

/*******************************************************************************
                                    Swaps
*******************************************************************************/

/// @dev The user tried to swap zero tokens.
error AmountGivenZero();

/// @dev The user attempted to swap a token for itself.
error CannotSwapSameToken();

/// @dev The user attempted to swap a token not in the pool.
error TokenNotRegistered();

/*******************************************************************************
                                Add Liquidity
*******************************************************************************/

/// @dev Add liquidity kind not supported.
error InvalidAddLiquidityKind();

/// @dev A required amountIn exceeds the maximum limit specified for the operation.
error AmountInAboveMax(IERC20 token, uint256 amount, uint256 limit);

/// @dev The BPT amount received from adding liquidity is below the minimum specified for the operation.
error BptAmountOutBelowMin(uint256 amount, uint256 limit);

/*******************************************************************************
                                Remove Liquidity
*******************************************************************************/

/// @dev Remove liquidity kind not supported.
error InvalidRemoveLiquidityKind();

/// @dev The actual amount out is below the minimum limit specified for the operation.
error AmountOutBelowMin(IERC20 token, uint256 amount, uint256 limit);

/// @dev The required BPT amount in exceeds the maximum limit specified for the operation.
error BptAmountInAboveMax(uint256 amount, uint256 limit);

/*******************************************************************************
                                 Fees
*******************************************************************************/

/// @dev Error raised when the protocol swap fee percentage exceeds the maximum allowed value.
error ProtocolSwapFeePercentageTooHigh();

/// @dev Error raised when the swap fee percentage exceeds the maximum allowed value.
error SwapFeePercentageTooHigh();

/*******************************************************************************
                                Queries
*******************************************************************************/

/// @dev A user tried to execute a query operation when they were disabled.
error QueriesDisabled();

/*******************************************************************************
                            Recovery Mode
*******************************************************************************/

/**
 * @dev Cannot enable recovery mode when already enabled.
 * @param pool The pool
 */
error PoolInRecoveryMode(address pool);

/**
 * @dev Cannot disable recovery mode when not enabled.
 * @param pool The pool
 */
error PoolNotInRecoveryMode(address pool);

/*******************************************************************************
                            Authentication
*******************************************************************************/

/**
 * @dev Error indicating the sender is not the Vault (e.g., someone is trying to call a permissioned function).
 * @param sender The account attempting to call a permissioned function
 */
error SenderIsNotVault(address sender);

/*******************************************************************************
                                    Pausing
*******************************************************************************/

/// @dev The caller specified a pause window period longer than the maximum.
error VaultPauseWindowDurationTooLarge();

/// @dev The caller specified a buffer period longer than the maximum.
error PauseBufferPeriodDurationTooLarge();

/// @dev A user tried to invoke an operation while the Vault was paused.
error VaultPaused();

/// @dev Governance tried to unpause the Vault when it was not paused.
error VaultNotPaused();

/// @dev Governance tried to pause the Vault after the pause period expired.
error VaultPauseWindowExpired();

/**
 * @dev A user tried to invoke an operation involving a paused Pool.
 * @param pool The paused pool
 */
error PoolPaused(address pool);

/**
 * @dev Governance tried to unpause the Pool when it was not paused.
 * @param pool The unpaused pool
 */
error PoolNotPaused(address pool);

/**
 * @dev Governance tried to pause a Pool after the pause period expired.
 * @param pool The pool
 */
error PoolPauseWindowExpired(address pool);

/**
 * @dev The caller is not the registered pause manager for the pool.
 * @param pool The pool
 */
error SenderIsNotPauseManager(address pool);

/*******************************************************************************
                                Miscellaneous
*******************************************************************************/

/// @dev Optional User Data should be empty in the current add / remove liquidity kind.
error UserDataNotSupported();

/// @dev The contract should not receive ETH.
error CannotReceiveEth();
