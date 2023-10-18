// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVaultErrors {
    /**
     * @dev Error indicating that a pool has already been registered.
     */
    error PoolAlreadyRegistered(address pool);

    /// @dev Error indicating that the pool has already been initialized. `initialize` may only be called once.
    error PoolAlreadyInitialized(address pool);

    /**
     * @dev Error indicating that a referenced pool has not been registered.
     */
    error PoolNotRegistered(address pool);

    /**
     * @dev Error indicating that a referenced pool has not been registered.
     */
    error PoolNotInitialized(address pool);

    /**
     * @dev Error indicating an attempt to register an invalid token.
     */
    error InvalidToken();

    /**
     * @dev Error indicating a token was already registered (i.e., a duplicate).
     */
    error TokenAlreadyRegistered(IERC20 tokenAddress);

    /**
     * @dev Error indicating the sender is not the Vault (e.g., someone is trying to call a permissioned function).
     */
    error SenderIsNotVault(address sender);

    /**
     * @dev
     */
    error TokensMismatch(address tokenA, address tokenB);

    /**
     * @dev
     */
    error PoolHasNoTokens(address pool);

    /**
     * @dev
     */
    error JoinAboveMax();

    /**
     * @dev
     */
    error InvalidEthInternalBalance();

    /**
     * @dev
     */
    error ExitBelowMin();

    /**
     * @dev
     */
    error SwapDeadline();

    /**
     * @dev
     */
    error AmountGivenZero();

    /**
     * @dev
     */
    error CannotSwapSameToken();

    /**
     * @dev
     */
    error TokenNotRegistered();

    /**
     * @dev
     */
    error SwapLimit(uint256, uint256);

    /**
     * @dev
     */
    error BptAmountBelowMin();

    /**
     * @dev
     */
    error BptAmountAboveMax();

    /**
     * @dev
     */
    error BalanceNotSettled();

    /**
     * @dev
     */
    error WrongHandler(address, address);

    /**
     * @dev
     */
    error NoHandler();

    /**
     * @dev
     */
    error HandlerOutOfBounds(uint256);

    /**
     * @dev
     */
    error QueriesDisabled();

    /**
     * @dev
     */
    error HookCallFailed();

    /**
     * @dev
     */
    error RouterNotTrusted();
}
