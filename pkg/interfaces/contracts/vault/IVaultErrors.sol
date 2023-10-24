// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVaultErrors {
    /// @dev A pool has already been registered.
    error PoolAlreadyRegistered(address pool);

    /// @dev The pool has already been initialized. `initialize` may only be called once.
    error PoolAlreadyInitialized(address pool);

    /// @dev A referenced pool has not been registered.
    error PoolNotRegistered(address pool);

    /// @dev A referenced pool has not been initialized.
    error PoolNotInitialized(address pool);

    /// @dev An attempt to register an invalid token.
    error InvalidToken();

    /// @dev A token was already registered (i.e., a duplicate).
    error TokenAlreadyRegistered(IERC20 tokenAddress);

    /// @dev Indicates the number of pool tokens is below the minimum allowed.
    error MinTokens();

    /// @dev Indicates the number of pool tokens is above the maximum allowed.
    error MaxTokens();

    /// @dev The sender is not the Vault (e.g., someone is trying to call a permissioned function).
    error SenderIsNotVault(address sender);

    /// @dev The token list passed into an operation does not match the pool tokens in the pool.
    error TokensMismatch(address tokenA, address tokenB);

    /// @dev The pool has not been initialized.
    error PoolHasNoTokens(address pool);

    /// @dev A required amountIn exceeds the maximum limit specified in the join.
    error JoinAboveMax();

    /// @dev The actual bptAmountOut is below the minimum limit specified in the exit.
    error ExitBelowMin();

    /// @dev The swap transaction was not mined before the specified deadline timestamp.
    error SwapDeadline();

    /// @dev The user tried to swap zero tokens.
    error AmountGivenZero();

    /// @dev The user attempted to swap a token for itself.
    error CannotSwapSameToken();

    /// @dev A token involved in a swap is invalid (e.g., the zero address).
    error TokenNotRegistered();

    /// @dev An amount in or out has exceeded the limit specified in the swap request.
    error SwapLimit(uint256, uint256);

    /// @dev The BPT amount involved in the operation is below the absolute minimum.
    error BptAmountBelowAbsoluteMin();

    /// @dev The BPT amount received from adding liquidity is below the minimum specified for the operation.
    error BptAmountBelowMin();

    /// @dev The BPT amount requested from removing liquidity is above the maximum specified for the operation.
    error BptAmountAboveMax();

    /// @dev A transient accounting operation completed with outstanding token deltas.
    error BalanceNotSettled();

    /// @dev In transient accounting, a handler is attempting to execute an operation out of order.
    error WrongHandler(address, address);

    /// @dev A user called a Vault function (swap, add/remove liquidity) outside the invoke context.
    error NoHandler();

    /// @dev The caller attempted to access a handler at an invalid index.
    error HandlerOutOfBounds(uint256);

    /// @dev Pool does not support adding liquidity proportionally.
    error DoesNotSupportAddLiquidityProportional(address pool);

    /// @dev A user tried to execute a query operation when they were disabled.
    error QueriesDisabled();

    /// @dev The pool has returned false to a callback, indicating the transaction should revert.
    error CallbackFailed();

    /// @dev An unauthorized Router tried to call a permissioned function (i.e., using the Vault's token allowance).
    error RouterNotTrusted();
}
